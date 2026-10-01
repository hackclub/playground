# Whether a participant is in #playground on the Hack Club Slack, and adding
# them when they say yes. It calls the Slack Web API with the Slack app's
# token, credentials slack.token. The app needs channels:read and
# channels:manage, and must be a member of the channel. Without a token the
# prompt stays hidden. In development and tests the Fake stands in.
class SlackChannel
  API = "https://slack.com/api"
  CHANNEL = "C0ASBTMS82H".freeze # #playground

  # A Slack answer of ok: false.
  class Error < StandardError; end

  # Members held in memory for tests and development, by Slack id.
  module Fake
    def self.members = @members ||= Set.new
    def self.reset! = @members = Set.new
  end

  def self.token = Rails.application.credentials.dig(:slack, :token)
  def self.configured? = FakeServices.on? || token.present?

  # True only when Slack says the participant is not in the channel. Any
  # failure to ask counts as not knowing, so the prompt stays hidden.
  def self.absent?(slack_id)
    return false unless configured? && slack_id.present?
    !member?(slack_id)
  rescue HttpJson::Error, Error, SocketError, Timeout::Error, SystemCallError => e
    Rails.logger.warn("slack channel check failed: #{e.class}: #{e.message.first(120)}")
    false
  end

  def self.member?(slack_id)
    return Fake.members.include?(slack_id) if FakeServices.on?
    members.include?(slack_id)
  end

  # Adds the participant. Already in the channel counts as added.
  def self.invite(slack_id)
    if FakeServices.on?
      Fake.members << slack_id
      return
    end
    call(:post, "conversations.invite", form: { channel: CHANNEL, users: slack_id })
  rescue Error => e
    raise unless e.message == "already_in_channel"
  ensure
    Rails.cache.delete("slack-channel-members")
  end

  # Every member id, held for five minutes. Slack pages the list at most
  # 1000 members at a time.
  def self.members
    Rails.cache.fetch("slack-channel-members", expires_in: 5.minutes) do
      ids = []
      cursor = nil
      loop do
        body = call(:get, "conversations.members", query: { channel: CHANNEL, limit: 1000, cursor: cursor }.compact)
        ids.concat(body.fetch("members"))
        cursor = body.dig("response_metadata", "next_cursor").presence
        break unless cursor
      end
      ids.to_set
    end
  end

  def self.call(method, name, query: nil, form: nil)
    url = "#{API}/#{name}#{"?#{query.to_query}" if query}"
    _, body = HttpJson.request(method, url, headers: { "Authorization" => "Bearer #{token}" }, form:)
    raise Error, "unreadable answer from #{name}" unless body.is_a?(Hash)
    raise Error, body["error"].to_s unless body["ok"]
    body
  end
  private_class_method :call
end
