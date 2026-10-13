# A direct message from the Slack app to one person. chat.postMessage with
# the person's Slack id as the channel opens a DM from the app, and needs
# only the chat:write scope:
# https://docs.slack.dev/reference/methods/chat.postMessage/
# It uses the token of SlackChannel. In development and tests the Fake
# stands in.
class SlackDm
  # A Slack answer of ok: false. The message is Slack's error code.
  class Error < StandardError; end

  # Messages held in memory for tests and development, oldest first.
  module Fake
    def self.sent = @sent ||= []
    def self.reset! = @sent = []
  end

  def self.configured? = SlackChannel.configured?

  # Posts text, in Slack mrkdwn, to the person. Raises Error on ok: false,
  # and HttpJson::Error on a status that isn't 2xx, such as 429.
  def self.post(slack_id, text)
    if FakeServices.on?
      Fake.sent << { channel: slack_id, text: }
      return
    end
    _, body = HttpJson.request(:post, "#{SlackChannel::API}/chat.postMessage",
                               headers: { "Authorization" => "Bearer #{SlackChannel.token}" },
                               json: { channel: slack_id, text:, unfurl_links: false })
    raise Error, "unreadable answer from chat.postMessage" unless body.is_a?(Hash)
    raise Error, body["error"].to_s unless body["ok"]
    body
  end
end
