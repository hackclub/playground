require "test_helper"

# The chat.postMessage call, with HttpJson standing in for Slack.
class SlackDmTest < ActiveSupport::TestCase
  test "it posts the text to the Slack id, and raises Slack's error on ok: false" do
    calls = []
    answer = { "ok" => true }
    fake_request = ->(method, url, **opts) { calls << [ method, url, opts ]; [ nil, answer ] }
    with_methods(FakeServices, on?: -> { false }) do
      with_methods(HttpJson, request: fake_request) do
        SlackDm.post("U0KID", "hi")
        method, url, opts = calls.last
        assert_equal :post, method
        assert_equal "https://slack.com/api/chat.postMessage", url
        assert_equal({ channel: "U0KID", text: "hi", unfurl_links: false }, opts[:json])
        assert opts[:headers]["Authorization"].start_with?("Bearer ")

        answer = { "ok" => false, "error" => "missing_scope" }
        error = assert_raises(SlackDm::Error) { SlackDm.post("U0KID", "hi") }
        assert_equal "missing_scope", error.message
      end
    end
  end

  test "the fake records the message" do
    SlackDm::Fake.reset!
    SlackDm.post("U0KID", "hi")
    assert_equal [ { channel: "U0KID", text: "hi" } ], SlackDm::Fake.sent
  ensure
    SlackDm::Fake.reset!
  end

  private

  def with_methods(target, replacements)
    originals = replacements.keys.to_h { [ it, target.method(it) ] }
    replacements.each { |name, body| target.define_singleton_method(name, &body) }
    yield
  ensure
    originals.each { |name, original| target.define_singleton_method(name, &original) }
  end
end
