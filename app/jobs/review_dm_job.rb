# Sends the participant the Slack DM for a review outcome (ReviewDm). Slack's
# rate limit or a lost connection waits a minute and tries again, up to five
# times. Every other problem is logged in ReviewDm and the job ends.
class ReviewDmJob < ApplicationJob
  queue_as :default

  retry_on ReviewDm::TryLater, wait: 1.minute, attempts: 5 do |job, error|
    Rails.logger.warn("review dm: gave up on ship #{job.arguments.first}: #{error.message.first(120)}")
  end

  def perform(ship_id, state) = ReviewDm.deliver(ship_id, state)
end
