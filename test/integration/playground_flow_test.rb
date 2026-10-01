require "test_helper"

# The whole program, as a participant and as the two admins:
# track, ship, review, fraud, redeem, fulfill.
class PlaygroundFlowTest < ActionDispatch::IntegrationTest
  PET = { name: "rock pet", description: "a rock that walks along your taskbar and naps",
          code_url: "https://github.com/pet/rock", playable_url: "https://pet.itch.io/rock",
          ship_message_url: "https://hackclub.slack.com/archives/C0C51NCK1DG/p1759012345678901",
          hackatime_projects: [ "rock-pet", "rock-pet-art" ] }.freeze

  test "a participant ships, an admin reviews and passes fraud, the participant redeems, an admin fulfills" do
    participant = log_in("participant")
    post dev_hackatime_path
    # A new pet starts with a name and a description. Edit adds the rest.
    post projects_path, params: { project: PET.slice(:name, :description) }
    project = participant.projects.last
    assert_redirected_to project_path(project)
    patch project_path(project), params: { project: PET.except(:name, :description) }
    assert_redirected_to project_path(project)
    # Three screenshots, and the last is moved up to be the cover.
    3.times do
      upload_screenshot(project)
      assert_response :created
    end
    ids = project.reload.screenshots.pluck("id")
    patch order_project_screenshots_path(project), params: { ids: ids.rotate(-1) }, as: :json
    shots = project.reload.screenshot_urls

    # Unshipped hours come from the two linked Hackatime projects.
    assert project.reload.tracked_seconds.positive?
    get dashboard_path
    assert_select ".legend", /unshipped/

    get checks_project_path(project)
    assert_select ".checks li", 0
    assert_match "all set", response.body
    post ship_project_path(project)
    ship = project.ships.last
    assert ship.pending?
    # The ship message belongs to this ship. The next ship needs its own.
    assert_equal PET[:ship_message_url], ship.snapshot["ship_message_url"]
    assert_equal PET[:ship_message_url], AirtableFields.ship(ship)["Ship Message URL"]
    assert_nil project.reload.ship_message_url
    # The ship keeps every screenshot in order, and the cover on its own.
    assert_equal shots, ship.snapshot["screenshots"]
    assert_equal shots.first, ship.snapshot["screenshot_url"]
    assert_equal [ { "url" => shots.first } ], AirtableFields.ship(ship)["Screenshot"], "the Unified DB gets the cover"
    assert_equal project.tracked_seconds, ship.claimed_seconds
    assert_equal ship.claimed_seconds, participant.hours.pending_seconds
    assert_equal 0, participant.hours.unshipped_seconds

    # One admin reviews and deflates by a quarter hour.
    reset!
    log_in("admin")
    get admin_review_path
    assert_redirected_to admin_ship_path(ship, stage: "review")
    follow_redirect!
    assert_select ".readme h1", "rock"
    assert_equal shots, css_select("img.shot").map { it["src"] }, "the review shows every screenshot, cover first"
    assert_select "img.shot[alt='screenshot 2 of 3']"
    assert_select ".readme script", 0
    approved = ship.claimed_seconds / 3600.0 - 0.25
    post review_admin_ship_path(ship), params: { verdict: "approve", approved_hours: approved, judgement: "runs, readme is good", feedback: "nice rock" }
    assert_redirected_to admin_review_path
    ship.reload
    assert_equal "approved", ship.review_status
    assert_equal "pending", ship.fraud_status
    assert ship.pending?, "hours stay pending until fraud passes"

    # froppii runs the fraud stage.
    reset!
    log_in("froppii")
    get admin_fraud_path
    assert_redirected_to admin_ship_path(ship, stage: "fraud")
    post fraud_admin_ship_path(ship), params: { verdict: "pass" }
    ship.reload
    assert ship.approved?
    assert_equal ship.review_seconds, ship.approved_seconds
    assert_includes Justification.new(ship).to_s, "deflated by 15m"

    # The participant has 3h+ approved: stickers unlock, the shirt does not.
    reset!
    log_in("participant")
    assert participant.reload.hours.approved_seconds >= Goal.find("stickers").seconds
    get new_redemption_path(goal_key: "stickers")
    assert_select "input[name='shipping[line_1]'][value='15 Falls Road']"
    assert_select "input[name='shipping[first_name]'][value='Participant']"
    # Its fields keep it out of Turbo's preview, as on the other form pages.
    assert_select "meta[name='turbo-cache-control'][content='no-preview']", 1
    # The parcel can go to a different name than the account's.
    post redemptions_path(goal_key: "stickers"), params: { shipping: {
      first_name: "Sam", last_name: "Dev", line_1: "15 Falls Road", line_2: "Unit 2", city: "Shelburne",
      state: "VT", postal_code: "05482", country: "US", phone_number: "+1 802 555 0100" } }
    assert_redirected_to dashboard_path, "stays inside ship.exe instead of loading the desktop in it"
    redemption = participant.redemptions.sole
    assert_equal "Sam", redemption.address["first_name"]
    assert_equal "15 Falls Road", redemption.address["line_1"]
    get new_redemption_path(goal_key: "stickers")
    assert_redirected_to dashboard_path
    assert_equal 1, participant.redemptions.count, "each goal redeems once"
    get new_redemption_path(goal_key: "shirt")
    assert_redirected_to dashboard_path
    assert_nil participant.redemptions.find_by(goal_key: "shirt")

    # Fulfillment: the address is hidden until revealed, and the reveal is logged.
    reset!
    admin = log_in("admin")
    get admin_fulfillment_path
    assert_redirected_to admin_redemption_path(redemption)
    follow_redirect!
    assert_no_match "15 Falls Road", response.body
    post reveal_admin_redemption_path(redemption)
    assert_match "15 Falls Road", response.body
    assert AuditEvent.exists?(actor: admin, subject: redemption, action: "address.reveal")
    post verdict_admin_redemption_path(redemption), params: { verdict: "fulfill", tracking: "LA123" }
    assert_equal "fulfilled", redemption.reload.status
  end

  test "an unverified participant can track but not ship" do
    user = log_in("unverified")
    post dev_hackatime_path
    post projects_path, params: { project: PET }
    project = user.projects.last
    upload_screenshot(project)
    post ship_project_path(project)
    assert_empty project.ships
    assert_match "verified", flash[:alert]
  end

  test "the gate blocks a source-only release, a missing screenshot, and a missing README" do
    user = log_in("participant")
    post dev_hackatime_path
    post projects_path, params: { project: PET.merge(playable_url: "https://github.com/pet/rock/releases/latest") }
    OfflineGithub.release = Github::Release.new(tag: "v1", url: "x", assets: [])
    OfflineGithub.repo = OfflineGithub::REPO.with(readme: false, commits: 1)
    gate = SubmitGate.new(user.reload.projects.last)
    assert_equal %i[readme playable screenshot].sort, gate.blockers.map(&:key).sort
    assert_equal %i[playable_host commits], gate.warnings.map(&:key), "a link off itch.io only warns"
  end

  test "changes needed gives the hours back, and a reship claims only new time" do
    user = log_in("participant")
    post dev_hackatime_path
    post projects_path, params: { project: PET }
    project = user.projects.last
    upload_screenshot(project)
    post ship_project_path(project)
    ship = project.ships.last
    ship.return_for_changes!(by: User.find_or_create_by!(hca_id: "ident!x") { it.admin = true }, judgement: "no", feedback: "add install steps")
    assert_equal project.reload.tracked_seconds, user.hours.unshipped_seconds
    # The first ship took its message with it, so the reship needs another.
    post ship_project_path(project)
    assert_equal 1, project.ships.count
    project.update!(ship_message_url: PET[:ship_message_url].succ)
    post ship_project_path(project)
    assert_equal 2, project.ships.count
    assert_equal project.tracked_seconds, project.ships.last.claimed_seconds
  end

  test "fraud ban rejects the ship and bans the participant" do
    user = log_in("participant")
    post dev_hackatime_path
    post projects_path, params: { project: PET }
    upload_screenshot(user.projects.last)
    post ship_project_path(user.projects.last)
    ship = user.ships.last
    admin = User.create!(hca_id: "ident!a2", admin: true, first_name: "A")
    ship.approve_review!(by: admin, seconds: ship.claimed_seconds, judgement: "ok", feedback: nil)
    ship.ban_for_fraud!(by: admin, notes: "autotyper heartbeats")
    assert ship.reload.rejected?
    assert user.reload.banned?
    assert_equal 0, user.hours.approved_seconds
  end

  test "an admin never gets their own ship, and a live claim hides an item from the other admin" do
    participant = log_in("participant")
    post dev_hackatime_path
    post projects_path, params: { project: PET }
    upload_screenshot(participant.projects.last)
    post ship_project_path(participant.projects.last)
    ship = participant.ships.last

    reset!
    log_in("admin")
    get admin_review_path
    assert_redirected_to admin_ship_path(ship, stage: "review")
    follow_redirect!

    reset!
    log_in("froppii")
    get admin_review_path
    assert_response :success
    assert_select "h2", /queue is clear/
  end

  test "participants cannot reach the admin" do
    log_in("participant")
    get admin_root_path
    assert_response :not_found
  end
end

class RevealWithoutTurboTest < ActionDispatch::IntegrationTest
  # Turbo ignores a 200 answer to a form POST, so the reveal form must opt out.
  test "the reveal button submits without Turbo" do
    user = User.create!(hca_id: "ident!r", verification_status: "verified", ysws_eligible: true)
    r = user.redemptions.create!(goal_key: "stickers", address: { "line_1" => "1 Road" })
    log_in("admin")
    get admin_redemption_path(r)
    assert_select "form[data-turbo=false] button", "reveal address"
  end
end

class ShippingFormTest < ActionDispatch::IntegrationTest
  setup do
    @user = log_in("participant")
    project = @user.projects.create!(name: "p", tracked_seconds: 3 * 3600)
    admin = User.create!(hca_id: "ident!sf-admin", admin: true)
    ship = project.ships.create!(user: @user, claimed_seconds: 3 * 3600)
    ship.approve_review!(by: admin, seconds: 3 * 3600, judgement: "ok", feedback: nil)
    ship.pass_fraud!(by: admin)
  end

  test "missing required fields re-render the form and save nothing" do
    post redemptions_path(goal_key: "stickers"), params: { shipping: { first_name: "", line_1: "", city: "X", country: "US" } }
    assert_response :unprocessable_entity
    assert_select ".banner.alert", /First name can't be blank/
    assert_empty @user.redemptions
  end

  test "newlines and control characters are flattened, and extra fields are ignored" do
    post redemptions_path(goal_key: "stickers"), params: { shipping: {
      first_name: "Sam\nEvil", line_1: "1 Road\r\n\u0000", city: "Town", country: "US", admin: "true" } }
    address = @user.redemptions.sole.address
    assert_equal "Sam Evil", address["first_name"]
    assert_equal "1 Road", address["line_1"]
    refute address.key?("admin")
  end
end

class DescriptionChecksTest < ActiveSupport::TestCase
  def failed(description)
    user = User.create!(hca_id: "ident!desc-#{SecureRandom.hex(3)}")
    SubmitGate.new(user.projects.create!(name: "p", description:)).blockers.map(&:key) & %i[description description_length]
  end

  test "a missing description and a short one are separate failures" do
    assert_equal [ :description ], failed(nil)
    assert_equal [ :description ], failed("   ")
    assert_equal [ :description_length ], failed("asdfasdfasdf")
    assert_empty failed("a rock that walks along your taskbar")
  end

  test "a short description says how long it is" do
    user = User.create!(hca_id: "ident!desc-len")
    check = SubmitGate.new(user.projects.create!(name: "p", description: "asdfasdfasdf")).checks.find { it.key == :description_length }
    assert_match "yours is 12", check.detail
  end
end

class GoalCardsTest < ActionDispatch::IntegrationTest
  test "cards show one progress line and say what to do next" do
    user = log_in("participant")
    user.projects.create!(name: "p", hackatime_projects: [], tracked_seconds: (1.3 * 3600).round)
    get dashboard_path
    assert_select ".goal .progress", text: "1.3/2 h"
    assert_select ".goal", text: /approved hours/, count: 0
    assert_select ".goal", text: /to go/, count: 0
  end
end

class ShipChecklistTest < ActionDispatch::IntegrationTest
  test "only what is left to do is listed, with an exclamation mark" do
    user = log_in("participant")
    project = user.projects.create!(name: "p", description: "a rock that walks along your taskbar")
    get checks_project_path(project)
    assert_select ".checks li .icon", text: "!"
    assert_select ".checks li", text: /your pet needs a name/, count: 0
    assert_select ".checks li", text: /your pet needs a Hackatime project/
    assert_select ".checks", text: /✗|✓/, count: 0
  end
end

# A new pet asks for its name and description only. Its ship popup lists the
# rest, each with its field, and edit still shows every field.
class NewPetFormTest < ActionDispatch::IntegrationTest
  LATER = %w[project[code_url] project[playable_url] project[hackatime_projects][]].freeze

  setup do
    @user = log_in("participant")
    post dev_hackatime_path
  end

  test "the new form has a name and a description only, and never asks Hackatime" do
    without_hackatime do
      get new_project_path
      assert_select "input[name='project[name]']"
      assert_select "textarea[name='project[description]']"
      LATER.each { assert_select "[name='#{it}']", 0 }
      assert_select "input[type=file]", 0

      post projects_path, params: { project: { name: "", description: "a rock that naps" } }
      assert_response :unprocessable_entity
      assert_select ".banner.alert", /Name can't be blank/
      assert_select "textarea[name='project[description]']", text: "a rock that naps"
      LATER.each { assert_select "[name='#{it}']", 0 }
    end
    assert_empty @user.projects
  end

  test "a pet with a name and a description lands on its page, whose ship popup lists what is left" do
    post projects_path, params: { project: { name: "rock", description: "a rock that walks along your taskbar" } }
    project = @user.projects.sole
    assert_redirected_to project_path(project)
    assert_empty project.hackatime_projects
    follow_redirect!
    assert_select "a[href='#{checks_project_path(project)}']", "ship"
    assert_select ".checks", 0
    assert_select "input[type=file], .shots-grid, [data-controller~='screenshot-upload']", 0, "the pet page has nothing to upload with"

    get checks_project_path(project)
    assert_select ".checks li", text: /your pet needs a Hackatime project/ do
      assert_select "input[type=checkbox][name='project[hackatime_projects][]'][value='rock-pet']"
    end
    assert_select ".checks li", text: /your pet needs a link to its code/ do
      assert_select "input[name='project[code_url]']"
    end
    assert_select ".checks li", text: /the shipped link needs to work/ do
      assert_select "input[name='project[playable_url]']"
    end
    assert_select ".checks li", text: /your pet needs a screenshot/ do
      assert_select ".shots-grid .shot-cell.add"
    end

    get edit_project_path(project)
    LATER.each { assert_select "[name='#{it}']" }
    assert_select "input[type=file]"
  end

  test "edit still refuses a Hackatime project another pet has" do
    @user.projects.create!(name: "first", hackatime_projects: [ "rock-pet" ])
    post projects_path, params: { project: { name: "second", description: "another rock" } }
    second = @user.projects.find_by!(name: "second")
    get edit_project_path(second)
    assert_select "input[value='rock-pet']", 0, "a taken project is not offered"

    patch project_path(second), params: { project: { code_url: "https://github.com/pet/second", hackatime_projects: [ "rock-pet", "frog-widget" ] } }
    assert_response :unprocessable_entity
    assert_select ".banner.alert", /already linked to another pet: rock-pet/
    assert_select "input[name='project[code_url]'][value='https://github.com/pet/second']"
    assert_select "input[value='frog-widget']"
    assert_empty second.reload.hackatime_projects
  end

  private

  def without_hackatime
    original = Hackatime.method(:for)
    Hackatime.define_singleton_method(:for) { |_user| raise "the new pet form asked Hackatime" }
    yield
  ensure
    Hackatime.define_singleton_method(:for, original)
  end
end
