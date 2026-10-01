# The prompt at the top of ship.exe's dashboard: a signed up participant who
# is not in #playground can ask the Slack app to add them, or hide the prompt.
class SlackChannelsController < ApplicationController
  before_action :require_login

  def join
    SlackChannel.invite(current_user.slack_id)
    redirect_to dashboard_path, notice: "you're in! look for #playground in Slack."
  rescue HttpJson::Error, SlackChannel::Error, SocketError, Timeout::Error, SystemCallError => e
    Rails.logger.warn("slack channel invite failed: #{e.class}: #{e.message.first(120)}")
    redirect_to dashboard_path, alert: "we couldn't add you just now. join #playground from the link in welcome.txt."
  end

  def dismiss
    current_user.update!(slack_prompt_dismissed_at: Time.current)
    redirect_to dashboard_path
  end
end
