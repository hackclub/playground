require "test_helper"

# Only Hackatime time inside the program window counts: on the dashboard, on
# the pet page, in the picker, at ship, and in the admin review. Each fake
# Hackatime project is a stretch of time ending a set time before now (see
# Hackatime::Fake), so each test travels to one edge of the window.
class ProgramTimeTest < ActionDispatch::IntegrationTest
  WINDOW = ProgramWindow.load({ starts_at: "2026-09-25 17:00", ends_at: "2026-10-09 17:00" })
  START = "5pm Eastern time on September 25, 2026".freeze
  STREAM = { "Accept" => "text/vnd.turbo-stream.html, text/html, application/xhtml+xml" }.freeze
  READY = { description: "a rock that walks along your taskbar", code_url: "https://github.com/pet/rock",
            ship_message_url: "https://hackclub.slack.com/archives/C0C51NCK1DG/p1759012345678901", playable_url: "https://pet.itch.io/rock",
            screenshots: [ { "id" => "shot", "key" => "shot.webp", "url" => "https://playground.hackclub-assets.com/shot.webp" } ] }.freeze

  setup { ProgramWindow.current = WINDOW }

  def start_at(time, linked)
    travel_to time
    @user = log_in("participant")
    post dev_hackatime_path
    @rock = Hackatime::Fake.new(@user).catalog.first.total_seconds
    @pet = @user.projects.create!(name: "rock", hackatime_projects: linked, **READY)
  end

  def picker = css_select("ul.picker li").to_h { [ it.at("strong").text, it.at("span.muted").text.squish ] }
  def checked = css_select("ul.picker input[checked]").map { it["value"] }

  test "before 5pm Eastern on the first day nothing counts, and the dashboard says when time starts to count" do
    start_at WINDOW.starts_at - 1.minute, %w[rock-pet rock-pet-art]
    get dashboard_path
    assert_select ".panel p.muted", "time counts from #{START}."
    assert_select ".legend", /unshipped 0m/
    assert_equal 0, @pet.reload.tracked_seconds

    get project_path(@pet)
    assert_select "p", /tracked 0m · unshipped 0m/

    # Only the pet's own projects are listed, kept although they have no time yet.
    get edit_project_path(@pet)
    assert_equal({ "rock-pet" => "no time counted yet", "rock-pet-art" => "no time counted yet" }, picker)
    assert_equal %w[rock-pet rock-pet-art], checked

    # With nothing linked, the picker says what it lists.
    @pet.update!(hackatime_projects: [])
    get edit_project_path(@pet)
    assert_select "fieldset p.muted", "no Hackatime projects with time since #{START} yet. start coding and they'll appear here."
  end

  test "on the first day only the time since 5pm Eastern counts" do
    start_at WINDOW.starts_at + 1.hour, %w[rock-pet rock-pet-art]
    get dashboard_path
    assert_select ".panel p.muted", text: /time counts from/, count: 0
    assert_select ".legend", /unshipped 55m/
    assert_equal 55 * 60, @pet.reload.tracked_seconds

    get project_path(@pet)
    assert_select "p", /tracked 55m · unshipped 55m/

    get edit_project_path(@pet)
    assert_equal({ "rock-pet" => "55m · last active 5 minutes ago", "rock-pet-art" => "no time counted yet" }, picker)
    assert_select "ul.picker input[value=frog-widget], ul.picker input[value=dotfiles]", 0, "no time in the window, not linked here"
  end

  test "the last day counts up to 5pm Eastern, and a ship after the end claims the window's time without a new blocker" do
    start_at WINDOW.ends_at - 1.minute, %w[rock-pet rock-pet-art]
    get dashboard_path
    assert_equal @rock + 50 * 60, @pet.reload.tracked_seconds
    get edit_project_path(@pet)
    assert_equal %w[rock-pet rock-pet-art frog-widget], picker.keys

    # An hour after the end, rock-pet's last 55 minutes fall after it.
    travel_to WINDOW.ends_at + 1.hour
    get checks_project_path(@pet)
    assert_select ".checks li", 0
    post ship_project_path(@pet)
    ship = @pet.ships.sole
    assert_equal @rock - 55 * 60 + 50 * 60, ship.claimed_seconds
    assert_equal({ "starts_at" => "2026-09-25T17:00:00-04:00", "ends_at" => "2026-10-09T17:00:00-04:00" }, ship.snapshot["window"])
    assert_equal 0, @pet.reload.unshipped_seconds
    assert_match "rock-pet-art (50m), 2026-09-25 17:00 to 2026-10-09 17:00 US Eastern time", Justification.new(ship).hackatime_projects
  end

  test "a linked project with no time in the window stays in the picker and through a save" do
    start_at WINDOW.starts_at + 1.hour, %w[rock-pet dotfiles]
    get edit_project_path(@pet)
    assert_equal "no time counted yet", picker["dotfiles"]
    assert_equal %w[rock-pet dotfiles], checked

    # What the edit form sends back untouched.
    patch project_path(@pet), params: { project: { name: "rock", hackatime_projects: [ "", "rock-pet", "dotfiles" ] } }
    assert_redirected_to project_path(@pet)
    assert_equal %w[rock-pet dotfiles], @pet.reload.hackatime_projects

    # ship.exe's picker keeps it too.
    get checks_project_path(@pet, shown: [ "hackatime_projects" ]), headers: STREAM
    assert_select "#ship-check-hackatime_projects input[type=checkbox][value=dotfiles][checked]"
    assert_select "#ship-check-hackatime_projects li", text: /dotfiles\s+no time counted yet/
  end

  test "a ship from before the window keeps its hours and claims none of the window's time" do
    start_at WINDOW.starts_at + 1.hour, %w[rock-pet]
    before = @pet.ships.create!(user: @user, claimed_seconds: 10.hours.to_i, created_at: WINDOW.starts_at - 2.days,
                                snapshot: { "tracked_seconds" => 10.hours.to_i, "taken_at" => "2026-09-23T10:00:00Z" })
    get dashboard_path
    assert_select ".legend", /pending 10h 0m.*unshipped 55m/m
    assert_equal 55 * 60, @pet.reload.unshipped_seconds
    assert_equal 10.hours, before.reload.claimed_seconds
    assert_match "all time up to 2026-09-23", Justification.new(before).hackatime_projects, "stored ships stay as they were"
  end

  test "the admin review shows the live time inside the window" do
    start_at WINDOW.starts_at + 1.hour, %w[rock-pet]
    post ship_project_path(@pet)
    ship = @pet.ships.sole
    assert_equal 55 * 60, ship.claimed_seconds
    assert_match "rock-pet (55m), 2026-09-25 17:00 to 2026-09-25 18:00 US Eastern time", Justification.new(ship).to_s

    travel_to WINDOW.starts_at + 2.hours
    reset!
    log_in("admin")
    get admin_ship_path(ship, stage: "review")
    assert_select ".kv tr", text: /rock-pet\s*55m\s*now 1h 55m/
  end

  test "PROGRAM_STARTS_AT moves the start without a code edit" do
    ENV["PROGRAM_STARTS_AT"] = "2026-10-01 09:30"
    ProgramWindow.current = ProgramWindow.load
    start_at Time.utc(2026, 10, 1, 13, 29), %w[rock-pet]
    get dashboard_path
    assert_select ".panel p.muted", "time counts from 9:30am Eastern time on October 1, 2026."
    assert_equal 0, @pet.reload.tracked_seconds
  ensure
    ENV.delete("PROGRAM_STARTS_AT")
  end
end
