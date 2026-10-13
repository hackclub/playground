require "test_helper"

# Coding and art are deflated apart. Art is Lapse time. The AI cap cuts coding
# only, and art holds at 30% of the approved total (3/7 of the approved coding).
class ShipSplitReviewTest < ActiveSupport::TestCase
  setup do
    @user = User.create!(hca_id: "ident!split", email: "sp@example.com", first_name: "S", verification_status: "verified", ysws_eligible: true)
    @admin = User.create!(hca_id: "ident!spadm", admin: true)
    @project = @user.projects.create!(name: "pet", hackatime_projects: %w[a])
    @window = { "starts_at" => "2026-09-25T17:00:00-04:00", "ends_at" => "2026-10-09T17:00:00-04:00" }
  end

  # 5h claimed: 3h coding (1h of it ai coding) and 2h art.
  def ship(ai: 3600, art: 7200, claimed: 18_000)
    snap = { "projects" => { "a" => claimed }, "tracked_seconds" => claimed, "window" => @window, "taken_at" => "2026-10-02T12:00:00Z", "ai_coding_seconds" => ai }
    snap["lapse_seconds"] = art if art
    snap["lapses"] = [] if art
    @project.ships.create!(user: @user, claimed_seconds: claimed, snapshot: snap)
  end

  def approve(s, coding, art: nil, reason: nil)
    s.approve_review!(by: @admin, seconds: coding, art_seconds: art, judgement: "ok", feedback: nil, deflation_reason: reason)
    s
  end

  test "coding is the claim less the art, and the ai cap cuts coding only" do
    s = ship
    assert_equal 7200, s.art_claimed_seconds
    assert_equal 10_800, s.coding_claimed_seconds
    assert_equal 10_800 - 2400, s.ai_cap_seconds
  end

  test "art holds at 3/7 of the approved coding, with no reason" do
    s = approve(ship, 8400)
    assert_equal 8400, s.review_coding_seconds
    assert_equal 3600, s.review_art_seconds, "3/7 of 8400"
    assert_equal 12_000, s.review_seconds
    assert_in_delta 0.30, s.review_art_seconds.to_f / s.review_seconds, 0.0001
  end

  test "a lower coding figure lowers the art limit" do
    s = approve(ship, 7000, art: 7200, reason: "idle")
    assert_equal 3000, s.review_art_seconds
    assert_equal 10_000, s.review_seconds
  end

  test "art takes the reviewer's lower value when it needs a reason" do
    s = ship
    assert_raises(ArgumentError) { approve(s, 8400, art: 1800) }
    approve(s, 8400, art: 1800, reason: "mostly sketches")
    assert_equal [ 8400, 1800, 10_200 ], [ s.review_coding_seconds, s.review_art_seconds, s.review_seconds ]
  end

  test "a coding cut below the cap needs a reason, the ai cut alone does not" do
    assert_raises(ArgumentError) { approve(ship, 5000) }
    approve(ship, 8400)
  end

  test "the 36 second snap applies to coding and art" do
    s = approve(ship, 8400 - 20, art: 3600 - 30)
    assert_equal [ 8400, 3600 ], [ s.review_coding_seconds, s.review_art_seconds ]
  end

  test "a ship with no Lapse time has no art, and the old single figure still works" do
    s = approve(ship(art: nil, ai: 0), 18_000)
    assert_equal [ 18_000, 0, 18_000 ], [ s.review_coding_seconds, s.review_art_seconds, s.review_seconds ]
  end

  test "a ship with no lapses key counts no art" do
    assert_equal 0, ship(art: nil).art_claimed_seconds
  end

  test "an old ship with nil split columns reads as before" do
    s = ship
    s.update_columns(review_status: "approved", review_seconds: 15_600, state: "approved", approved_seconds: 15_600)
    assert_nil s.review_coding_seconds
    assert_not s.split_review?
    text = Justification.new(s).to_s
    assert_no_match(/Coding: claimed/, text)
    assert_includes text, "Approved by review: 4h 20m"
  end

  test "the justification names each part" do
    s = approve(ship, 7200, art: 7200, reason: "the middle was idle")
    s.pass_fraud!(by: @admin)
    text = Justification.new(s).to_s
    assert_includes text, "Coding: claimed 3h 0m, approved 2h 0m. Art (Lapse): claimed 2h 0m, approved 51m, held at 30% of the approved total."
    assert_includes text, "Coding deflated from 3h 0m to 2h 0m: ai coding time counted at a third, and further because the middle was idle."
    assert_includes text, "Art held at 30% of the approved total: 2h 0m to 51m."
    assert_includes Justification.new(s).deflation, "Coding deflated from 3h 0m to 2h 0m"
    assert_no_match(/the reviewer checked the Lapse time/, text)
  end

  test "a human cut on art says so with the reason" do
    s = approve(ship, 8400, art: 1800, reason: "mostly sketches")
    assert_includes Justification.new(s).deflation, "Art deflated from 2h 0m to 30m because mostly sketches."
  end
end
