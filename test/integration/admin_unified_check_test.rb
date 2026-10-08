require "test_helper"

# The fraud-stage list shows the Unified DB search result. UnifiedSearch.check
# is swapped for the test, so nothing reaches Airtable.
class AdminUnifiedCheckTest < ActionDispatch::IntegrationTest
  setup do
    participant = User.create!(hca_id: "ident!unified-check", verification_status: "verified", ysws_eligible: true)
    project = participant.projects.create!(name: "rock", code_url: "https://gitlab.com/pet/rock")
    @ship = project.ships.create!(user: participant, claimed_seconds: 3600, snapshot: { "code_url" => project.code_url })
    log_in("admin")
    UnifiedSearch.singleton_class.alias_method(:real_check, :check)
  end

  teardown do
    UnifiedSearch.singleton_class.alias_method(:check, :real_check)
  end

  def answer(result) = UnifiedSearch.define_singleton_method(:check) { |*, **| result }

  test "a match from another program warns with its details" do
    answer UnifiedSearch::Result.new(status: :warn, matches: [
      UnifiedSearch::Match.new(program: "Sleepover", approved_at: "2026-10-01", hours: 5, url: "https://gitlab.com/pet/rock", own: false)
    ])
    get admin_ship_path(@ship, stage: "fraud")
    assert_select "li.warn", /Sleepover, approved 2026-10-01, 5h/
  end

  test "no match is ok and a failure is a question mark" do
    answer UnifiedSearch::Result.new(status: :ok, matches: [])
    get admin_ship_path(@ship, stage: "fraud")
    assert_select "li.ok", /not in the Unified DB under another program/
    answer UnifiedSearch::Result.new(status: :unknown, matches: [], reason: "Unified DB search failed")
    get admin_ship_path(@ship, stage: "fraud")
    assert_select "li.warn .icon", "?"
    assert_select "li", /Unified DB search failed/
  end
end
