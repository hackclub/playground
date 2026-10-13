require "test_helper"

class JustificationTest < ActiveSupport::TestCase
  setup do
    @user = User.create!(hca_id: "ident!j1", email: "j@example.com", first_name: "J", verification_status: "verified", ysws_eligible: true)
    @admin = User.create!(hca_id: "ident!jadm", admin: true)
    @project = @user.projects.create!(name: "pet", hackatime_projects: %w[a b], tracked_seconds: 7260)
  end

  def snapshot(extra = {})
    { "projects" => { "a" => 3600, "b" => 3360 }, "tracked_seconds" => 7260, "hackatime_user_id" => "42", "trust_level" => "green",
      "taken_at" => "2026-10-02T12:00:00Z",
      "window" => { "starts_at" => "2026-09-25T17:00:00-04:00", "ends_at" => "2026-10-09T17:00:00-04:00" } }.merge(extra)
  end

  def ship(claimed: 7260, seconds: claimed, reason: nil, snap: snapshot)
    s = @project.ships.create!(user: @user, claimed_seconds: claimed, snapshot: snap)
    s.approve_review!(by: @admin, seconds:, judgement: "custom jumping physics, a save file", feedback: nil, deflation_reason: reason)
    s.pass_fraud!(by: @admin)
    s
  end

  test "projects get a date range each, the window follows once, and the combined total is stated" do
    text = Justification.new(ship).to_s
    assert_includes text, "Hackatime projects: a 9/25/2026-10/2/2026 (1h 0m), b 9/25/2026-10/2/2026 (56m), window 2026-09-25 17:00 to 2026-10-02 08:00 US Eastern time."
    assert_includes text, "Hackatime total for these projects together: 2h 1m (this can differ from the sum of the per-project totals)."
    assert_includes Justification.new(ship).hackatime_projects, "a 9/25/2026-10/2/2026 (1h 0m), b 9/25/2026-10/2/2026 (56m), window"
  end

  test "Lapse links appear only when the snapshot has Lapses" do
    assert_no_match(/Lapse links/, Justification.new(ship).to_s)
    lapses = [ { "id" => "x1", "title" => "first day", "duration" => 1800, "url" => "https://lapse.hackclub.com/timelapse/x1" },
               { "id" => "x2", "title" => "polish", "duration" => 600, "url" => "https://lapse.hackclub.com/timelapse/x2" } ]
    text = Justification.new(ship(snap: snapshot("lapses" => lapses))).to_s
    assert_includes text, "Lapse links: https://lapse.hackclub.com/timelapse/x1 (first day, 30m), https://lapse.hackclub.com/timelapse/x2 (polish, 10m)."
  end

  test "approving the form's rounded figure stores the claim and reads as no deflation" do
    s = ship(claimed: 13620, seconds: 13608)
    assert_equal 13620, s.review_seconds
    assert_includes Justification.new(s).to_s, "no deflation"
    assert_nil Justification.new(s).deflation
  end

  test "an older ship with a sub-minute deflation reads as no deflation" do
    s = ship
    s.update_columns(review_seconds: s.claimed_seconds - 12)
    assert_includes Justification.new(s).to_s, "no deflation"
    assert_nil Justification.new(s).deflation
  end

  test "a real deflation needs a reason and the text gives it" do
    error = assert_raises(ArgumentError) { ship(claimed: 7200, seconds: 3600) }
    assert_match "why", error.message
    s = ship(claimed: 7200, seconds: 3600, reason: "the second hour was idle.")
    assert_equal "Deflated from 2h 0m to 1h 0m because the second hour was idle.", Justification.new(s).deflation
    assert_includes Justification.new(s).to_s, "Deflated from 2h 0m to 1h 0m because the second hour was idle."
  end

  test "an update note keeps the earlier claims" do
    s = ship(snap: snapshot("previously_claimed_seconds" => 5400))
    assert_includes Justification.new(s).to_s, "Update: 1h 30m were claimed by earlier ships"
    assert_includes Justification.new(s).hackatime_projects, "earlier ships claimed 1h 30m"
  end

  test "the reviewer text is labelled as specific technical features" do
    assert_includes Justification.new(ship).to_s, "Specific technical features: custom jumping physics, a save file"
  end
end
