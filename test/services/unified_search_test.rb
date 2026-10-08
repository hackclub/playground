require "test_helper"

# The double-dip check against a stub client: nothing reaches Airtable.
class UnifiedSearchTest < ActiveSupport::TestCase
  Stub = Struct.new(:records, :error, :calls) do
    def search(table, formula:, fields:, **)
      (self.calls ||= []) << [ table, formula, fields ]
      raise error if error
      records
    end
  end

  def record(url, program, hours: 5, on: "2026-10-01")
    { "fields" => { "Code URL" => url, "YSWS–Name" => program, "Approved At" => on, "Override Hours Spent" => hours } }
  end

  test "normalizes urls" do
    assert_equal "github.com/a/b", UnifiedSearch.normalize("https://www.GitHub.com/A/B/tree/main/src")
    assert_equal "github.com/a/b", UnifiedSearch.normalize("http://github.com/a/b.git/")
    assert_equal "gitlab.com/a/b", UnifiedSearch.normalize("https://gitlab.com/a/b/-/blob/x")
    assert_equal "git.example.org/a/b/c", UnifiedSearch.normalize("https://git.example.org/a/b/c/")
  end

  test "blank or short value is not searched" do
    stub = Stub.new([])
    assert_equal :unknown, UnifiedSearch.check("", client: stub).status
    assert_equal :unknown, UnifiedSearch.check("https://a.b", client: stub).status
    assert_nil stub.calls
  end

  test "no token" do
    ENV.delete("AIRTABLE_UNIFIED_TOKEN")
    skip "credentials hold a token" if UnifiedSearch.token
    result = UnifiedSearch.check("https://github.com/a/b")
    assert_equal :unknown, result.status
    assert_equal "no read token", result.reason
  end

  test "match from another program warns" do
    stub = Stub.new([ record("https://github.com/a/b", [ "Sleepover" ]) ])
    result = UnifiedSearch.check("https://github.com/a/b/", client: stub)
    assert_equal :warn, result.status
    assert_equal "Sleepover", result.matches.first.program
    assert_equal 5, result.matches.first.hours
    assert_includes stub.calls.first[1], "FIND(LOWER('github.com/a/b'), LOWER({Code URL}))"
    assert_equal UnifiedSearch::FIELDS, stub.calls.first[2]
  end

  test "own program only is shown apart" do
    result = UnifiedSearch.check("https://github.com/a/b", client: Stub.new([ record("https://github.com/a/b", [ "Playground" ]) ]))
    assert_equal :own_only, result.status
    assert result.matches.first.own
  end

  test "a longer repo name is not a match" do
    result = UnifiedSearch.check("https://github.com/a/b", client: Stub.new([ record("https://github.com/a/b-two", [ "Sleepover" ]) ]))
    assert_equal :ok, result.status
  end

  test "quotes and backslashes are escaped" do
    stub = Stub.new([])
    UnifiedSearch.check("https://git.example.org/a'b\\c", client: stub)
    assert_includes stub.calls.first[1], "LOWER('git.example.org/a\\'b\\\\c')"
  end

  test "no match" do
    assert_equal :ok, UnifiedSearch.check("https://github.com/a/b", client: Stub.new([])).status
  end

  test "api error is a result, not a raise" do
    result = UnifiedSearch.check("https://github.com/a/b", client: Stub.new([], HttpJson::Error.new("boom", status: 500)))
    assert_equal :unknown, result.status
    assert_equal "Unified DB search failed", result.reason
  end
end
