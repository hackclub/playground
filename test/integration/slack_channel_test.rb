require "test_helper"

# Swaps singleton methods for the block, and puts them back. Minitest 6 has
# no stub.
module Swap
  def swap(target, replacements)
    originals = replacements.keys.to_h { [ it, target.method(it) ] }
    replacements.each { |name, body| target.define_singleton_method(name, &(body.respond_to?(:call) ? body : proc { body })) }
    yield
  ensure
    originals.each { |name, original| target.define_singleton_method(name, &original) }
  end
end

# The prompt to join #playground at the top of ship.exe's dashboard.
class SlackChannelPromptTest < ActionDispatch::IntegrationTest
  include Swap

  PROMPT = "You don't seem to be in the #playground channel! Would you like to join?".freeze

  setup do
    SlackChannel::Fake.reset!
    @user = log_in("participant")
    @user.update!(slack_id: "U0SAMROCK")
  end

  teardown { SlackChannel::Fake.reset! }

  test "a participant outside the channel is asked, and Add me! adds them and hides the prompt" do
    get dashboard_path
    assert_select ".slack-prompt p", PROMPT
    assert_select ".slack-prompt button", text: "Add me!"
    assert_select ".slack-prompt button", text: "Don't show this message again"

    post join_slack_channel_path
    assert_redirected_to dashboard_path
    assert_includes SlackChannel::Fake.members, "U0SAMROCK"
    follow_redirect!
    assert_select ".slack-prompt", 0
    assert_select ".flash.notice", text: /you're in!/
  end

  test "Don't show this message again hides it for good, and leaves them out of the channel" do
    post dismiss_slack_channel_path
    assert_redirected_to dashboard_path
    assert_not_nil @user.reload.slack_prompt_dismissed_at
    get dashboard_path
    assert_select ".slack-prompt", 0
    assert_not_includes SlackChannel::Fake.members, "U0SAMROCK"
  end

  test "a member, or someone with no Slack id, or a banned account, is not asked" do
    SlackChannel::Fake.members << "U0SAMROCK"
    get dashboard_path
    assert_select ".slack-prompt", 0

    SlackChannel::Fake.reset!
    @user.update!(slack_id: nil)
    get dashboard_path
    assert_select ".slack-prompt", 0

    @user.update!(slack_id: "U0SAMROCK", banned_at: Time.current)
    get dashboard_path
    assert_select ".slack-prompt", 0
  end

  test "a failed add says so and stays on the dashboard" do
    swap(SlackChannel, invite: ->(_) { raise SlackChannel::Error, "not_in_channel" }) { post join_slack_channel_path }
    assert_redirected_to dashboard_path
    assert_match "couldn&#39;t add you", flash[:alert].to_s.gsub("'", "&#39;")
    assert_nil @user.reload.slack_prompt_dismissed_at
  end
end

# The Slack Web API side, with the network stubbed.
class SlackChannelApiTest < ActiveSupport::TestCase
  include Swap

  setup { Rails.cache.clear }

  def answering(*bodies, &)
    calls = []
    fake = ->(method, url, **opts) { calls << [ method, url, opts ]; [ nil, bodies.shift ] }
    swap(FakeServices, on?: false) do
      swap(SlackChannel, token: "xoxb-test") { swap(HttpJson, request: fake, &) }
    end
    calls
  end

  test "members are read page by page, and cached" do
    calls = answering(
      { "ok" => true, "members" => [ "U1" ], "response_metadata" => { "next_cursor" => "abc" } },
      { "ok" => true, "members" => [ "U2" ], "response_metadata" => { "next_cursor" => "" } }
    ) { assert SlackChannel.member?("U2") }
    assert_equal 2, calls.size
    assert_match "cursor=abc", calls.last[1]
    assert_equal({ "Authorization" => "Bearer xoxb-test" }, calls.first[2][:headers])
  end

  test "an answer of ok: false counts as not knowing, so no prompt" do
    answering({ "ok" => false, "error" => "missing_scope" }) do
      assert_not SlackChannel.absent?("U1")
    end
  end

  test "inviting posts the channel and the user, and already in the channel is fine" do
    calls = answering({ "ok" => false, "error" => "already_in_channel" }) { SlackChannel.invite("U1") }
    assert_equal :post, calls.first[0]
    assert_equal({ channel: "C0ASBTMS82H", users: "U1" }, calls.first[2][:form])
  end

  test "with no token and no fakes, the prompt stays hidden" do
    swap(FakeServices, on?: false) { swap(SlackChannel, token: nil) { assert_not SlackChannel.absent?("U1") } }
  end
end
