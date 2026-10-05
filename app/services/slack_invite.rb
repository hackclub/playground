# Adds each participant whose Hack Club Auth account links a Slack account to
# #playground, once. slack_invited_at records the add, so a person who leaves
# the channel is not added again. One at signup, and a sweep every hour for
# anyone missed. Without a token it does nothing.
class SlackInvite
  # conversations.invite is Tier 3, 50 or more calls a minute.
  PAUSE = 1.3
  # Slack errors that no later user can get past: stop and try next hour.
  STOP = %w[missing_scope not_in_channel invalid_auth not_authed token_revoked account_inactive channel_not_found].freeze

  class Stop < StandardError; end

  def self.pending = User.where(slack_invited_at: nil, banned_at: nil).where.not(slack_id: [ nil, "" ])

  # The signup add. A failure is logged, and the sweep tries again.
  def self.one(user)
    return unless user && SlackChannel.configured? && pending.exists?(id: user.id)
    add(user)
  rescue Stop
    nil
  end

  # Marks pending participants already in the channel, and adds the rest.
  # Returns how many it added.
  def self.sweep
    return 0 unless SlackChannel.configured?
    SlackChannel.forget_members
    members = SlackChannel.members
    added = 0
    pending.find_each do |user|
      if members.include?(user.slack_id)
        user.update!(slack_invited_at: Time.current)
      else
        added += 1 if add(user)
        sleep PAUSE unless FakeServices.on?
      end
    end
    Rails.logger.info("slack invite: added #{added}")
    added
  rescue Stop
    Rails.logger.warn("slack invite: stopped, trying again next run")
    added || 0
  end

  def self.add(user)
    SlackChannel.invite(user.slack_id)
    user.update!(slack_invited_at: Time.current)
    true
  rescue SlackChannel::Error => e
    Rails.logger.warn("slack invite failed for user #{user.id}: #{e.message.first(120)}")
    raise Stop if e.message.in?(STOP)
    false
  rescue HttpJson::Error, SocketError, Timeout::Error, SystemCallError => e
    Rails.logger.warn("slack invite failed for user #{user.id}: #{e.class}: #{e.message.first(120)}")
    raise Stop if e.is_a?(HttpJson::Error) && e.status == 429
    false
  end
  private_class_method :add
end
