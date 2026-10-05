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

# The add to #playground, with the fake channel standing in for Slack.
class SlackInviteTest < ActiveSupport::TestCase
  include Swap

  setup do
    SlackChannel::Fake.reset!
    User.update_all(slack_id: nil)
    @user = make_user("a", slack_id: "U0A")
  end

  teardown { SlackChannel::Fake.reset! }

  def make_user(name, **attrs)
    User.create!(hca_id: "ident!slack-#{name}", email: "#{name}@example.com", first_name: name, last_name: "Test",
                 verification_status: "verified", ysws_eligible: true, **attrs)
  end

  test "one adds the participant and records it" do
    SlackInvite.one(@user)
    assert_includes SlackChannel::Fake.members, "U0A"
    assert_not_nil @user.reload.slack_invited_at
  end

  test "one skips banned, unlinked, and already added participants" do
    banned = make_user("b", slack_id: "U0B", banned_at: Time.current)
    unlinked = make_user("c")
    SlackInvite.one(banned)
    SlackInvite.one(unlinked)
    assert_empty SlackChannel::Fake.members

    @user.update!(slack_invited_at: 1.day.ago)
    SlackInvite.one(@user)
    assert_empty SlackChannel::Fake.members
  end

  test "the sweep adds each pending participant once, and marks those already in the channel" do
    inside = make_user("d", slack_id: "U0D")
    SlackChannel::Fake.members << "U0D"
    assert_equal 1, SlackInvite.sweep
    assert_equal Set["U0A", "U0D"], SlackChannel::Fake.members
    assert_not_nil @user.reload.slack_invited_at
    assert_not_nil inside.reload.slack_invited_at
  end

  test "a person who left the channel is not added again" do
    SlackInvite.sweep
    SlackChannel::Fake.reset!
    assert_equal 0, SlackInvite.sweep
    assert_empty SlackChannel::Fake.members
  end

  test "a user Slack cannot find is left for the next sweep, and the rest are added" do
    other = make_user("e", slack_id: "U0E")
    invite = ->(id) { id == "U0A" ? raise(SlackChannel::Error, "user_not_found") : SlackChannel::Fake.members << id }
    swap(SlackChannel, invite:) { assert_equal 1, SlackInvite.sweep }
    assert_nil @user.reload.slack_invited_at
    assert_not_nil other.reload.slack_invited_at
  end

  test "a missing scope stops the sweep" do
    make_user("f", slack_id: "U0F")
    calls = 0
    swap(SlackChannel, invite: ->(_) { calls += 1; raise SlackChannel::Error, "missing_scope" }) do
      assert_equal 0, SlackInvite.sweep
    end
    assert_equal 1, calls
    assert_nil @user.reload.slack_invited_at
  end

  test "a rate limit stops the sweep" do
    make_user("g", slack_id: "U0G")
    calls = 0
    swap(SlackChannel, invite: ->(_) { calls += 1; raise HttpJson::Error.new("slow down", status: 429) }) do
      SlackInvite.sweep
    end
    assert_equal 1, calls
  end

  test "with no token and no fakes, nothing is added" do
    swap(FakeServices, on?: false) { swap(SlackChannel, token: nil) { assert_equal 0, SlackInvite.sweep } }
    assert_nil @user.reload.slack_invited_at
  end

  test "the job adds one participant, or sweeps with no id" do
    SlackInviteJob.perform_now(@user.id)
    assert_not_nil @user.reload.slack_invited_at

    other = make_user("h", slack_id: "U0H")
    SlackInviteJob.perform_now
    assert_not_nil other.reload.slack_invited_at
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

  test "inviting posts the channel and the user, and already in the channel is fine" do
    calls = answering({ "ok" => true }, { "ok" => false, "error" => "already_in_channel" }) { SlackChannel.invite("U1") }
    assert_equal :post, calls.last[0]
    assert_equal({ channel: "C0ASBTMS82H", users: "U1" }, calls.last[2][:form])
  end

  test "inviting joins the channel first" do
    calls = answering({ "ok" => true }, { "ok" => true }) { SlackChannel.invite("U1") }
    assert_equal %w[conversations.join conversations.invite], calls.map { it[1][/[a-z]+\.[a-z]+\z/] }
    assert_equal({ channel: "C0ASBTMS82H" }, calls.first[2][:form])
  end

  test "an answer of ok: false raises its error" do
    answering({ "ok" => true }, { "ok" => false, "error" => "missing_scope" }) do
      error = assert_raises(SlackChannel::Error) { SlackChannel.invite("U1") }
      assert_equal "missing_scope", error.message
    end
  end
end
