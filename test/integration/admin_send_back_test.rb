require "test_helper"

# A ship that passed review and waits for the fraud check can go back to the
# review queue, with no message to the participant.
class AdminSendBackTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup do
    clear_enqueued_jobs
    @admin = log_in("admin")
    @reviewer = User.create!(hca_id: "ident!rev", admin: true, first_name: "Rae")
    @user = User.create!(hca_id: "ident!sb", first_name: "Sam")
    @ship = @user.projects.create!(name: "pet").ships.create!(user: @user, claimed_seconds: 7200)
    @ship.approve_review!(by: @reviewer, seconds: 3600, art_seconds: 0, judgement: "fine", feedback: "nice", deflation_reason: "afk")
    @ship.update!(review_checklist: { "runs" => true })
    clear_enqueued_jobs
  end

  def dm_jobs = enqueued_jobs.select { it["job_class"] == "ReviewDmJob" }

  test "the model sends the ship back, keeps the old review in the audit, and sends no DM" do
    @ship.send_back_to_review!(by: @admin, reason: "not checked on Windows")
    @ship.reload
    assert_equal "pending", @ship.state
    assert_equal "pending", @ship.review_status
    assert_equal "waiting", @ship.fraud_status
    assert_nil @ship.reviewer
    assert_nil @ship.reviewed_at
    assert_nil @ship.review_seconds
    assert_nil @ship.review_judgement
    assert_nil @ship.review_feedback
    assert_nil @ship.review_deflation_reason
    assert_equal({}, @ship.review_checklist)
    assert_empty dm_jobs
    event = AuditEvent.find_by!(subject: @ship, action: "review.send_back")
    assert_equal @admin, event.actor
    assert_equal "not checked on Windows", event.data["reason"]
    assert_equal @reviewer.id, event.data["reviewer_id"]
    assert_equal @reviewer.display_name, event.data["reviewer_name"]
    assert_equal "fine", event.data["review_judgement"]
    assert_equal "afk", event.data["review_deflation_reason"]
    assert_equal 3600, event.data["review_seconds"]
  end

  test "the ship is back in the review queue in its original place" do
    later = @user.projects.create!(name: "later").ships.create!(user: @user, claimed_seconds: 3600)
    @ship.send_back_to_review!(by: @admin, reason: "recheck")
    assert_equal [ @ship.id, later.id ], Ship.awaiting_review.pluck(:id)
    assert_not_includes Ship.awaiting_fraud, @ship
  end

  test "the model refuses other states and a missing reason" do
    assert_raises(ArgumentError) { @ship.send_back_to_review!(by: @admin, reason: " ") }
    fresh = @user.projects.create!(name: "x").ships.create!(user: @user, claimed_seconds: 60)
    assert_raises(ArgumentError) { fresh.send_back_to_review!(by: @admin, reason: "r") }
    @ship.pass_fraud!(by: @reviewer)
    assert_raises(ArgumentError) { @ship.send_back_to_review!(by: @admin, reason: "r") }
    assert_equal "approved", @ship.reload.state
  end

  test "the action sends it back, clears fraud claims, and shows the history" do
    Claim.create!(claimable: @ship, stage: "fraud", user: @admin, heartbeat_at: Time.current)
    post send_back_admin_ship_path(@ship), params: { reason: "launch on Windows" }
    assert_redirected_to admin_ship_path(@ship, stage: "review")
    assert_equal "pending", @ship.reload.review_status
    assert_empty @ship.claims.where(stage: "fraud")
    assert_empty dm_jobs
    get admin_ship_path(@ship, stage: "review")
    assert_select "#send-back", count: 0
    assert_select "h2", text: "sent back to review"
    assert_select ".events li", text: /launch on Windows/
  end

  test "the action needs a reason and a ship that waits for fraud" do
    post send_back_admin_ship_path(@ship), params: { reason: "" }
    assert_equal 'write the "reason" box first. say why it goes back to review.', flash[:alert]
    assert_equal "approved", @ship.reload.review_status
    @ship.pass_fraud!(by: @reviewer)
    post send_back_admin_ship_path(@ship), params: { reason: "late" }
    assert_equal "this ship already moved on", flash[:alert]
  end

  test "the ship page shows the button in the fraud stage" do
    get admin_ship_path(@ship, stage: "fraud")
    assert_select "#send-back form[action=?]", send_back_admin_ship_path(@ship)
    assert_select "#send-back textarea[name=reason][required]"
  end

  test "an admin can't send back their own ship" do
    mine = @admin.projects.create!(name: "mine").ships.create!(user: @admin, claimed_seconds: 3600)
    mine.update!(review_status: "approved", fraud_status: "pending")
    post send_back_admin_ship_path(mine), params: { reason: "x" }
    assert_equal "approved", mine.reload.review_status
  end

  test "the overview lists every ship with its stage and filters by stage" do
    fresh = @user.projects.create!(name: "fresh").ships.create!(user: @user, claimed_seconds: 600)
    done = @user.projects.create!(name: "done").ships.create!(user: @user, claimed_seconds: 3600)
    done.approve_review!(by: @reviewer, seconds: 3600, art_seconds: 0, judgement: "ok", feedback: nil)
    done.pass_fraud!(by: @reviewer)
    done.update!(in_unified: true)
    get admin_ships_path
    @reviewer.reload
    assert_response :success
    assert_select "table tr", count: 4
    assert_select "a.btn", text: "all (3)"
    assert_select "a.btn", text: "awaiting review (1)"
    assert_select "a.btn", text: "awaiting fraud check (1)"
    assert_select "a.btn", text: "approved (1)"
    get admin_ships_path(stage: "awaiting_fraud")
    assert_select "table tr", count: 2
    assert_select "td a[href=?]", admin_ship_path(@ship), text: /pet #1/
    assert_select "td .badge", text: "awaiting fraud check"
    assert_select "td", text: /#{Regexp.escape(@reviewer.display_name)}/
    assert_select "td a", text: "send back to review"
    get admin_ships_path(stage: "approved")
    assert_select "table tr", count: 2
    assert_select "td", text: "yes"
    assert_select "td a", text: "send back to review", count: 0
    get admin_ships_path(stage: "awaiting_review")
    assert_select "td a", text: /fresh #1/
    get admin_ships_path(stage: "nonsense")
    assert_select "table tr", count: 4
    assert_equal "awaiting_review", fresh.stage
  end

  test "stage comes from state, review status, and fraud status" do
    assert_equal "awaiting_fraud", @ship.stage
    @ship.pass_fraud!(by: @reviewer)
    assert_equal "approved", @ship.stage
    other = @user.projects.create!(name: "o").ships.create!(user: @user, claimed_seconds: 600)
    assert_equal "awaiting_review", other.stage
    other.reject_review!(by: @reviewer, judgement: "no", feedback: "no")
    assert_equal "rejected", other.stage
    third = @user.projects.create!(name: "t").ships.create!(user: @user, claimed_seconds: 600)
    third.return_for_changes!(by: @reviewer, judgement: "x", feedback: "fix")
    assert_equal "changes_needed", third.stage
    assert_equal [ third.id ], Ship.in_stage("changes_needed").pluck(:id)
    assert_empty Ship.in_stage("bogus")
  end

  test "a reviewer bans for fraud from the review stage" do
    fresh = @user.projects.create!(name: "fresh").ships.create!(user: @user, claimed_seconds: 600)
    other = @user.projects.create!(name: "other").ships.create!(user: @user, claimed_seconds: 600)
    clear_enqueued_jobs
    get admin_ship_path(fresh, stage: "review")
    assert_select "button[name=verdict][value=ban]", text: "fraud: reject and ban"
    assert_select "textarea[name=notes]"
    post review_admin_ship_path(fresh), params: { verdict: "ban", notes: "", judgement: "copied" }
    assert_equal 'write the "evidence" box first. say what shows the fraud.', flash[:alert]
    assert_equal "pending", fresh.reload.state
    post review_admin_ship_path(fresh), params: { verdict: "ban", notes: "cloned repo", judgement: "copied" }
    fresh.reload
    assert_equal %w[rejected rejected banned], [ fresh.state, fresh.review_status, fresh.fraud_status ]
    assert_equal @admin, fresh.reviewer
    assert_equal @admin, fresh.fraud_reviewer
    assert_equal "copied", fresh.review_judgement
    assert_equal "cloned repo", fresh.fraud_notes
    assert_not_nil fresh.reviewed_at
    assert_equal "rejected", other.reload.state
    assert_equal "banned", other.fraud_status
    assert @user.reload.banned?
    assert_equal 1, dm_jobs.count { it["arguments"].first == fresh.id }
    assert_equal "rejected (banned)", Nokogiri::HTML(stage_html(fresh)).text
    post review_admin_ship_path(fresh), params: { verdict: "ban", notes: "again" }
    assert_equal "this ship already moved on", flash[:alert]
  end

  def stage_html(ship) = ApplicationController.helpers.extend(AdminHelper).stage_badge(ship)

  # 5h claimed, 2h of it art: coding caps at 3h and art at 3/7 of the coding.
  def sent_back_ship_with_art
    snap = { "projects" => { "a" => 18_000 }, "tracked_seconds" => 18_000, "ai_coding_seconds" => 0, "lapse_seconds" => 7200, "lapses" => [] }
    ship = @user.projects.create!(name: "arty").ships.create!(user: @user, claimed_seconds: 18_000, snapshot: snap)
    ship.approve_review!(by: @reviewer, seconds: 8400, art_seconds: 3600, judgement: "custom physics", feedback: "great", deflation_reason: "idle time")
    ship.send_back_to_review!(by: @admin, reason: "recheck")
    ship
  end

  test "a ship sent back opens its review with the earlier review filled in" do
    ship = sent_back_ship_with_art
    get admin_ship_path(ship, stage: "review")
    assert_select "textarea[name=judgement]", text: "custom physics"
    assert_select "textarea[name=feedback]", text: "great"
    assert_select "textarea[name=deflation_reason]", text: "idle time"
    assert_select "input[name=approved_hours][value=?]", "2.33"
    assert_select "input[name=approved_art_hours][value=?]", "1.0"
    assert_select "[data-deflate-target=total]", text: "3.33"
    assert_select "textarea[name=notes]", text: ""
    assert_select ".tick input[checked]", count: 0
  end

  test "the earlier review is held to the current cap" do
    ship = sent_back_ship_with_art
    ship.update!(snapshot: ship.snapshot.merge("ai_coding_seconds" => 9000))
    get admin_ship_path(ship, stage: "review")
    cap = (ship.reload.ai_cap_seconds / 3600.0).round(2)
    assert_select "input[name=approved_hours][value=?]", cap.to_s
  end

  test "what was typed before an error beats the earlier review" do
    ship = sent_back_ship_with_art
    post review_admin_ship_path(ship), params: { verdict: "changes", judgement: "typed", feedback: "", approved_hours: "1.5", approved_art_hours: "0.5", deflation_reason: "typed reason" }
    follow_redirect! if response.redirect?
    assert_select "textarea[name=judgement]", text: "typed"
    assert_select "textarea[name=deflation_reason]", text: "typed reason"
    assert_select "input[name=approved_hours][value=?]", "1.5"
    assert_select "input[name=approved_art_hours][value=?]", "0.5"
    assert_select "[data-deflate-target=total]", text: "2.0"
  end

  test "a ship never sent back opens with the defaults" do
    fresh = @user.projects.create!(name: "fresh").ships.create!(user: @user, claimed_seconds: 7200)
    get admin_ship_path(fresh, stage: "review")
    assert_select "textarea[name=judgement]", text: ""
    assert_select "input[name=approved_hours][value=?]", "2.0"
  end
end
