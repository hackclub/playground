require "test_helper"

# The review page: the form shows and prefills the cap, and a ship from before
# the cap gets its AI figure fetched once, or a warning when Hackatime won't say.
class AdminAiCapTest < ActionDispatch::IntegrationTest
  setup do
    @participant = User.create!(hca_id: "ident!ai-cap", verification_status: "verified", ysws_eligible: true, hackatime_access_token: "tok")
    @project = @participant.projects.create!(name: "rock", hackatime_projects: [ "rock-pet" ])
    log_in("admin")
  end

  def ship(snapshot) = @project.ships.create!(user: @participant, claimed_seconds: 13620, snapshot: snapshot)

  test "the form shows the ai time and prefills the cap" do
    s = ship("ai_coding_seconds" => 4200)
    get admin_ship_path(s, stage: "review")
    assert_select "p.muted", /ai coding: 1h 10m, counts at most a third/
    assert_select "input#approved_hours[value='3.01'][max='3.01']"
  end

  test "a ship with no figure gets one from Hackatime and stores it" do
    s = ship({ "window" => { "starts_at" => "2026-09-25T17:00:00-04:00", "ends_at" => "2026-10-09T17:00:00-04:00" } })
    Hackatime::Fake.ai_seconds = 4200
    get admin_ship_path(s, stage: "review")
    assert_equal 4200, s.reload.snapshot["ai_coding_seconds"]
  ensure
    Hackatime::Fake.ai_seconds = nil
  end

  test "an unknown figure warns and does not cap" do
    s = ship({})
    get admin_ship_path(s, stage: "review")
    assert_select ".banner", /ai coding time unknown, check Hackatime/
    assert_select "input#approved_hours[value='3.78']"
  end
end
