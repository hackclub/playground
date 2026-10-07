require "test_helper"

class AdminShipEmailTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup do
    @participant = User.create!(hca_id: "ident!em-#{SecureRandom.hex(3)}", email: "em@example.com", verification_status: "verified", ysws_eligible: true)
    @ship = @participant.projects.create!(name: "rock").ships.create!(user: @participant, claimed_seconds: 3600)
    log_in("admin")
    clear_enqueued_jobs
  end

  def mail_jobs = enqueued_jobs.select { it["job_class"] == "ActionMailer::MailDeliveryJob" }

  test "asking for changes enqueues one email, and a repeated post enqueues none" do
    2.times { post review_admin_ship_path(@ship), params: { verdict: "changes", judgement: "no", feedback: "Add a screenshot." } }
    assert_equal 1, mail_jobs.size
  end

  test "the fraud pass of an approved review enqueues the approval email" do
    post review_admin_ship_path(@ship), params: { verdict: "approve", approved_hours: "1", judgement: "ok" }
    assert_empty mail_jobs
    2.times { post fraud_admin_ship_path(@ship), params: { verdict: "pass" } }
    assert_equal 1, mail_jobs.size
  end
end
