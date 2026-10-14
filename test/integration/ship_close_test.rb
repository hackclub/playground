require "test_helper"

# After the program window ends no pet ships, except one whose latest ship
# needs changes, until the same close as prize claiming.
class ShipCloseTest < ActionDispatch::IntegrationTest
  STREAM = { "Accept" => "text/vnd.turbo-stream.html, text/html, application/xhtml+xml" }.freeze
  READY = { description: "a rock that walks along your taskbar", code_url: "https://github.com/pet/rock",
            ship_message_url: "https://hackclub.slack.com/archives/C0C51NCK1DG/p1759012345678901", playable_url: "https://pet.itch.io/rock", hackatime_projects: [ "rock-pet" ],
            screenshots: [ { "id" => "shot", "key" => "shot.webp", "url" => "https://playground.hackclub-assets.com/shot.webp" } ] }.freeze
  WINDOW = ProgramWindow.load({ starts_at: "2000-01-01 00:00", ends_at: "2026-10-19 02:00" })

  setup do
    ProgramWindow.current = WINDOW
    travel_to WINDOW.ends_at - 1.hour
    @user = log_in("participant")
    post dev_hackatime_path
    @pet = @user.projects.create!(READY.merge(name: "rock"))
  end

  test "before the end a pet ships as now" do
    get projects_path
    assert_select ".muted", text: /shipping closed|resubmit by/, count: 0
    post ship_project_path(@pet), headers: STREAM
    assert_redirected_to project_path(@pet)
    assert @pet.ships.sole.pending?
  end

  test "a new ship after the end is refused and its button is gone" do
    travel_to WINDOW.ends_at
    get project_path(@pet)
    assert_select "a.btn.primary", text: "ship", count: 0
    assert_select ".muted", "shipping closed Oct 19"
    post ship_project_path(@pet), headers: STREAM
    assert_response :unprocessable_entity
    assert_select "#ship-checks .banner.alert", "not yet: shipping closed Oct 19"
    assert_empty @pet.ships
  end

  test "a pet with changes needed can ship again until the close, then not" do
    # The fake's dotfiles project ended 40 days before, so its 12 hours stay inside the window.
    @pet.update_columns(hackatime_projects: [ "dotfiles" ])
    ship = @pet.ships.create!(user: @user, claimed_seconds: 60)
    ship.return_for_changes!(by: User.create!(hca_id: "ident!ship-close-admin", admin: true), judgement: "ok", feedback: "fix the readme")
    travel_to WINDOW.ends_at + 1.day
    get project_path(@pet)
    assert_select "a.btn.primary", "ship"
    assert_select ".muted", "resubmit by Oct 26"
    post ship_project_path(@pet), headers: STREAM
    assert_redirected_to project_path(@pet)
    assert_equal 2, @pet.ships.reload.count

    @pet.ships.last.update_columns(state: "changes_needed", review_status: "changes_needed")
    @pet.update_columns(ship_message_url: READY[:ship_message_url])
    travel_to WINDOW.redeem_ends_at - 1.minute
    post ship_project_path(@pet), headers: STREAM
    assert_redirected_to project_path(@pet)
    assert_equal 3, @pet.ships.reload.count

    @pet.ships.last.update_columns(state: "changes_needed", review_status: "changes_needed")
    @pet.update_columns(ship_message_url: READY[:ship_message_url])
    travel_to WINDOW.redeem_ends_at
    get project_path(@pet)
    assert_select ".muted", "shipping closed Oct 26"
    post ship_project_path(@pet), headers: STREAM
    assert_response :unprocessable_entity
    assert_equal 3, @pet.ships.reload.count
  end

  test "a pet whose latest ship is pending, approved, or rejected cannot ship after the end" do
    ship = @pet.ships.create!(user: @user, claimed_seconds: 3600)
    travel_to WINDOW.ends_at + 1.day
    %w[pending approved rejected].each do |state|
      ship.update_columns(state:)
      assert WINDOW.ship_closed_for?(@pet.reload), state
    end
  end
end
