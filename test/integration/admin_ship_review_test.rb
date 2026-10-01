require "test_helper"

# The admin's ship page: deflation presets on the verdict, and a Telescreen
# link to the participant's own page.
class AdminShipReviewTest < ActionDispatch::IntegrationTest
  setup do
    @participant = User.create!(hca_id: "ident!rev-#{SecureRandom.hex(3)}", email: "rev@example.com", verification_status: "verified",
                                ysws_eligible: true, hackatime_user_id: "4242")
    @project = @participant.projects.create!(name: "rock")
    @ship = @project.ships.create!(user: @participant, claimed_seconds: 4 * 3600, snapshot: { "hackatime_user_id" => "4242" })
    log_in("admin")
  end

  test "the verdict offers 15, 30, 50, and 75 percent of the claimed hours, and the field takes any value" do
    get admin_ship_path(@ship, stage: "review")
    assert_response :ok
    presets = css_select("#verdict button[data-percent]")
    assert_equal [ "15", "30", "50", "75" ], presets.map { it["data-percent"] }
    assert_equal [ "15% · 0.6h", "30% · 1.2h", "50% · 2.0h", "75% · 3.0h" ], presets.map { it.text.strip }
    assert presets.all? { it["type"] == "button" }, "a preset fills the field and does not submit"
    assert_select "#verdict[data-deflate-claimed-value='4.0'][novalidate]"
    assert_select "#verdict input[name=approved_hours][data-deflate-target=hours]"
  end

  test "the art share marks Lapse time over the 30% cap, and the checklist names the cap" do
    lapse = { "id" => "abc123", "title" => "drawing the rock", "duration" => 4032, "project" => "rock", "url" => "https://lapse.hackclub.com/timelapse/abc123" }
    @ship.update!(snapshot: { "lapses" => [ lapse ], "lapse_seconds" => 4032 })
    get admin_ship_path(@ship, stage: "review")
    assert_select "strong:not(.late)", "28%"
    assert_match "(cap 30%)", response.body
    assert_match "art counts at most 30% of approved hours", response.body
    assert_select "label.tick", /art is at most 30% of the hours/

    @ship.update!(snapshot: { "lapses" => [ lapse.merge("duration" => 4464) ], "lapse_seconds" => 4464 })
    get admin_ship_path(@ship, stage: "review")
    assert_select "strong.late", "31%"
  end

  test "the Telescreen link opens the participant's page by Hackatime id, and the home page with no id" do
    get admin_ship_path(@ship, stage: "review")
    assert_select "a[href=?]", "https://telescreen.hackclub.com/subjects/4242", "Telescreen"

    @participant.update!(hackatime_user_id: "9001")
    @ship.update!(snapshot: {})
    get admin_ship_path(@ship, stage: "review")
    assert_select "a[href=?]", "https://telescreen.hackclub.com/subjects/9001", "Telescreen"

    @participant.update!(hackatime_user_id: nil)
    get admin_ship_path(@ship, stage: "review")
    assert_select "a[href=?]", "https://telescreen.hackclub.com", "Telescreen"
  end
end
