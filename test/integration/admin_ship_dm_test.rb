require "test_helper"

class AdminShipDmTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup do
    @participant = User.create!(hca_id: "ident!dm-#{SecureRandom.hex(3)}", email: "dm@example.com", slack_id: "U0DM",
                                verification_status: "verified", ysws_eligible: true)
    @ship = @participant.projects.create!(name: "rock").ships.create!(user: @participant, claimed_seconds: 3600)
    log_in("admin")
    clear_enqueued_jobs
  end

  def dm_jobs = enqueued_jobs.select { it["job_class"] == "ReviewDmJob" }

  test "asking for changes enqueues one DM, and a repeated post enqueues none" do
    2.times { post review_admin_ship_path(@ship), params: { verdict: "changes", judgement: "no", feedback: "Add a screenshot." } }
    assert_equal 1, dm_jobs.size
  end

  test "the fraud pass of an approved review enqueues the approval DM" do
    post review_admin_ship_path(@ship), params: { verdict: "approve", approved_hours: "1", judgement: "ok" }
    assert_empty dm_jobs
    2.times { post fraud_admin_ship_path(@ship), params: { verdict: "pass" } }
    assert_equal 1, dm_jobs.size
  end

  test "a rejection enqueues one DM" do
    2.times { post review_admin_ship_path(@ship), params: { verdict: "reject", judgement: "no", feedback: "Not a pet." } }
    assert_equal 1, dm_jobs.size
  end
end
