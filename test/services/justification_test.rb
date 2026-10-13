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

  AI = 4200 # 1h 10m of ai coding

  def ai_ship(ai: AI, claimed: 13620, seconds: nil, reason: nil)
    cap = (claimed - ai * 2 / 3.0).round
    ship(claimed:, seconds: seconds || cap, reason:, snap: snapshot("ai_coding_seconds" => ai))
  end

  test "the cap is claimed less two thirds of the ai coding time, and never below zero" do
    s = @project.ships.create!(user: @user, claimed_seconds: 13620, snapshot: snapshot("ai_coding_seconds" => AI))
    assert_equal 13620 - 2800, s.ai_cap_seconds
    s.update!(snapshot: snapshot("ai_coding_seconds" => 99_999))
    assert_equal 4540, s.ai_cap_seconds, "ai time is never more than the claim, so a third remains"
    s.update!(snapshot: snapshot)
    assert_equal 13620, s.ai_cap_seconds, "no figure, no cap"
  end

  test "approving clamps to the cap and the prefilled figure needs no reason" do
    s = @project.ships.create!(user: @user, claimed_seconds: 13620, snapshot: snapshot("ai_coding_seconds" => AI))
    prefill = ((s.ai_cap_seconds / 3600.0).round(2) * 3600).round
    s.approve_review!(by: @admin, seconds: prefill, judgement: "ok", feedback: nil)
    assert_equal 10820, s.review_seconds
    t = @project.ships.create!(user: @user, claimed_seconds: 13620, snapshot: snapshot("ai_coding_seconds" => AI))
    t.approve_review!(by: @admin, seconds: 13620, judgement: "ok", feedback: nil)
    assert_equal 10820, t.review_seconds, "a higher figure is cut to the cap"
  end

  test "a cut below the cap still needs a reason" do
    s = @project.ships.create!(user: @user, claimed_seconds: 13620, snapshot: snapshot("ai_coding_seconds" => AI))
    assert_raises(ArgumentError) { s.approve_review!(by: @admin, seconds: 3600, judgement: "ok", feedback: nil) }
  end

  test "the text states the ai time and an ai-only cut" do
    s = ai_ship
    text = Justification.new(s).to_s
    assert_includes text, "Hackatime ai coding time: 1h 10m, counted at a third (23m), per the AI coding heartbeats rule."
    assert_includes text, "Deflated from 3h 47m to 3h 0m: ai coding time counted at a third."
    assert_equal "Hackatime ai coding time: 1h 10m, counted at a third (23m), per the AI coding heartbeats rule. Deflated from 3h 47m to 3h 0m: ai coding time counted at a third.", Justification.new(s).deflation
  end

  test "a further human cut appends its reason" do
    s = ai_ship(seconds: 7200, reason: "the rest was idle")
    assert_includes Justification.new(s).deflation, "Deflated from 3h 47m to 2h 0m: ai coding time counted at a third, and further because the rest was idle."
  end

  test "no ai time says none, and no figure says nothing" do
    assert_includes Justification.new(ai_ship(ai: 0)).to_s, "Hackatime ai coding time: none."
    assert_nil Justification.new(ai_ship(ai: 0)).deflation
    assert_no_match(/ai coding/, Justification.new(ship).to_s)
  end

  test "an update ship counts only the ai time earlier ships did not" do
    ProgramWindow.current = ProgramWindow.load({ starts_at: "2026-09-25 17:00", ends_at: "2026-10-09 17:00" })
    travel_to Time.zone.parse("2026-10-02 12:00") do
      @project.ships.create!(user: @user, claimed_seconds: 3600, snapshot: snapshot("ai_coding_seconds" => 900))
      Hackatime::Fake.ai_seconds = 2000
      assert_equal 1100, Shipper.ai_coding(@project, @user, ProgramWindow.current.starts_at, ProgramWindow.current.ends_at)
      Hackatime::Fake.ai_seconds = 500
      assert_equal 0, Shipper.ai_coding(@project, @user, ProgramWindow.current.starts_at, ProgramWindow.current.ends_at), "never below 0"
    end
  ensure
    Hackatime::Fake.ai_seconds = nil
  end

  test "a failed call stores nil and warns" do
    broken = Object.new
    broken.define_singleton_method(:ai_coding_seconds) { |*, **| raise HttpJson::Error.new("down", status: 503) }
    Hackatime.singleton_class.alias_method(:real_for, :for)
    Hackatime.define_singleton_method(:for) { |_| broken }
    warnings = []
    assert_nil Shipper.ai_coding(@project, @user, 1.day.ago, Time.current, warnings)
    assert_match(/ai coding time unavailable/, warnings.sole)
  ensure
    Hackatime.singleton_class.alias_method(:for, :real_for)
  end
end
