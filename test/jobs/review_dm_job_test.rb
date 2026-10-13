require "test_helper"

class ReviewDmJobTest < ActiveJob::TestCase
  test "Slack's rate limit puts the job back in the queue a minute later" do
    original = ReviewDm.method(:deliver)
    ReviewDm.define_singleton_method(:deliver) { |*| raise ReviewDm::TryLater, "ratelimited" }
    ReviewDmJob.perform_now(1, "approved")
    assert_enqueued_with(job: ReviewDmJob, args: [ 1, "approved" ])
  ensure
    ReviewDm.define_singleton_method(:deliver, &original)
  end
end
