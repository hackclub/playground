require "test_helper"

# A ship whose repo is shipped on Stardance is reviewed there. The review page
# warns and refuses the approve, but changes and reject stay open. A project
# with a ship in the Unified DB stays with playground. Stardance's database is
# OfflineStardance.
class AdminStardanceTest < ActionDispatch::IntegrationTest
  CODE = "https://github.com/pet/rock".freeze

  setup do
    participant = User.create!(hca_id: "ident!stardance-review", verification_status: "verified", ysws_eligible: true)
    @project = participant.projects.create!(name: "rock", code_url: CODE)
    @ship = @project.ships.create!(user: participant, claimed_seconds: 3600, snapshot: { "code_url" => CODE })
    log_in("admin")
    OfflineStardance.urls = [ "https://GitHub.com/pet/rock.git" ]
  end

  def approve = post(review_admin_ship_path(@ship), params: { verdict: "approve", approved_hours: 1, judgement: "ok" })

  test "the review page warns and turns the approve button off" do
    get admin_ship_path(@ship, stage: "review")
    assert_select ".banner", /shipped on Stardance, so it's reviewed there/
    assert_select "button[value=approve][disabled]"
    assert_select "button[value=changes]:not([disabled])"
    assert_select "button[value=reject]:not([disabled])"
  end

  test "a direct approve is refused with the reason, and changes and reject go through" do
    approve
    assert_redirected_to admin_ship_path(@ship, stage: "review")
    assert_equal "This project is shipped on Stardance, so it's reviewed there.", flash[:alert]
    assert_equal "pending", @ship.reload.review_status

    post review_admin_ship_path(@ship), params: { verdict: "changes", judgement: "no", feedback: "Reship on Stardance only." }
    assert_equal "changes_needed", @ship.reload.review_status
  end

  test "a repo not shipped on Stardance reviews as usual" do
    OfflineStardance.urls = [ "https://github.com/pet/other" ]
    get admin_ship_path(@ship, stage: "review")
    assert_select ".banner", text: /Stardance/, count: 0
    assert_select "button[value=approve]:not([disabled])"
    approve
    assert_equal "approved", @ship.reload.review_status
  end

  test "an outage lets the reviewer approve, with a note" do
    OfflineStardance.error = StardanceMcp::Error.new("down")
    get admin_ship_path(@ship, stage: "review")
    assert_select ".muted", /Could not check whether this repo is shipped on Stardance/
    approve
    assert_equal "approved", @ship.reload.review_status
  end

  test "a project with a ship in the Unified DB is never blocked" do
    @project.ships.create!(user: @ship.user, claimed_seconds: 60, state: "approved", in_unified: true)
    get admin_ship_path(@ship, stage: "review")
    assert_select ".banner", text: /Stardance/, count: 0
    approve
    assert_equal "approved", @ship.reload.review_status
  end
end
