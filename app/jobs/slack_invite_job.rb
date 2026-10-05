# Adds participants to #playground (SlackInvite). With a user id, that one
# participant at signup. Without, the hourly sweep.
class SlackInviteJob < ApplicationJob
  queue_as :default

  def perform(user_id = nil)
    user_id ? SlackInvite.one(User.find_by(id: user_id)) : SlackInvite.sweep
  end
end
