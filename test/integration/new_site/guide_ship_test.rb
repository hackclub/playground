require "test_helper"

# The guide's Ship it step holds the pet's ship list itself, the one on its
# ship checklist page: the participant fills in each field and ships there.
# Each save, check, and ship goes back to the guide. The list's own page
# stays as it was.
class NewSiteGuideShipTest < ActionDispatch::IntegrationTest
  include NewSiteTests
  STREAM = { "Accept" => "text/vnd.turbo-stream.html, text/html, application/xhtml+xml" }.freeze
  READY = { description: "a rock that walks along your taskbar", code_url: "https://github.com/pet/rock",
            ship_message_url: "https://hackclub.slack.com/archives/C0C51NCK1DG/p1759012345678901", playable_url: "https://pet.itch.io/rock",
            screenshots: [ { "id" => "shot", "key" => "shot.webp", "url" => "https://playground.hackclub-assets.com/shot.webp" } ] }.freeze
  BACK = "/guide/publish#ship".freeze

  setup do
    @user = log_in("participant")
    post dev_hackatime_path
    @project = @user.projects.create!(name: "rock", hackatime_projects: [ "rock-pet" ])
  end

  test "with no pet, or a pet with no Hackatime project, the step points back to the pick step" do
    @project.destroy!
    get guide_ship_path
    assert_select "#ship-step a[href=?]", "/guide/scene#pick-project", "pick your pet's Hackatime project"
    assert_select "#ship-checks", 0
    @user.projects.create!(name: "pebble")
    get guide_ship_path
    assert_select "#ship-step a[href=?]", "/guide/scene#pick-project"
    assert_select "#ship-checks", 0
  end

  test "on the guide's page the list loads after the page, into the Ship it frame, and the back button loads it again" do
    get "/guide/publish"
    assert_select "section[aria-labelledby=ship] turbo-frame#ship-step[src=?][target=_top]", guide_ship_path, text: /checking rock/
    assert_select "#ship-checks", 0
    assert_select "meta[name=turbo-cache-control][content=no-cache]"
    # The step keeps its intro line and its line about the requirements.
    assert_select "section[aria-labelledby=ship] p", /Shipping sends your pet and its hours to a reviewer/
    assert_select "section[aria-labelledby=ship] p.muted", /by shipping, you confirm your pet meets the/
  end

  test "the step holds the pet's ship list, each check with its field, and no second requirements line" do
    get guide_ship_path
    assert_select "turbo-frame#ship-step .guide-do-title", "ship rock"
    assert_select "#ship-step #ship-checks[data-controller=ship-checks][data-ship-checks-url-value=?]", checks_project_path(@project, from: "guide")
    assert_select ".requirements-note", 0
    assert_select "#ship-check-description textarea[name='project[description]']"
    assert_select "#ship-check-code_url input[type=url][name='project[code_url]']"
    assert_select "#ship-check-playable_url input[type=url][name='project[playable_url]']"
    assert_select "#ship-check-ship_message_url input[type=url][name='project[ship_message_url]']"
    assert_select "#ship-check-screenshot #ship-screenshot .shots-editor[data-screenshot-upload-url-value=?]", project_screenshots_path(@project)
    assert_select "#ship-check-screenshot .shots-editor[data-screenshot-upload-order-url-value=?]", order_project_screenshots_path(@project)
    # Each field's form says it comes from the guide.
    forms = css_select("#ship-checks form.fix")
    assert_equal 4, forms.size
    forms.each { assert_equal "guide", css_select(it, "input[name=from]").first&.[]("value") }
    assert_select "#ship-checks button[disabled]", "ship"
    assert_select "#ship-checks [role=status]", "fix these first"
    # The read-only list and the buttons to the checklist page are gone.
    assert_select ".guide-do-checks", 0
    assert_select "#ship-step a[href=?]", checks_project_path(@project), 0
  end

  test "a save from the guide comes back as the guide's list, and without JavaScript goes back to the guide's Ship it step" do
    patch project_path(@project), params: { checks: 1, from: "guide", shown: %w[description code_url], project: { description: READY[:description] } }, headers: STREAM
    assert_response :ok
    assert_select "turbo-stream[action=replace][target=ship-checks][method=morph]"
    assert_select "#ship-check-description.ok"
    assert_select "#ship-check-code_url.todo"
    assert_select ".requirements-note", 0
    assert_select "#ship-checks[data-ship-checks-url-value=?]", checks_project_path(@project, from: "guide")
    assert_select "#ship-checks form.fix input[name=from][value=guide]"
    assert_equal READY[:description], @project.reload.description

    patch project_path(@project), params: { checks: 1, from: "guide", project: { code_url: READY[:code_url] } }
    assert_redirected_to BACK
    assert_equal READY[:code_url], @project.reload.code_url
  end

  test "after an upload or a reorder, the list asks again the guide's way" do
    get checks_project_path(@project, from: "guide", shown: [ "screenshot" ]), headers: STREAM
    assert_select "#ship-check-screenshot.todo"
    assert_select ".requirements-note", 0
    upload_screenshot(@project)
    assert_response :created
    get checks_project_path(@project, from: "guide", shown: [ "screenshot" ]), headers: STREAM
    assert_select "#ship-check-screenshot.ok"
    assert_select "#ship-checks[data-ship-checks-url-value=?]", checks_project_path(@project, from: "guide")
  end

  test "ready, the pet ships from the guide, which then shows it in review" do
    @project.update!(READY)
    get guide_ship_path
    assert_select "#ship-checks li[data-check]", 0
    assert_select "#ship-checks form[action=?] input[name=from][value=guide]", ship_project_path(@project)
    assert_select "#ship-checks form[action=?] button", ship_project_path(@project), text: /\Aship \d+h \d+m\z/

    # The step turns to the review in place, marked just done, so the next
    # step and the hours beside the guide ask again.
    post ship_project_path(@project), params: { from: "guide" }, headers: STREAM
    assert_response :ok
    assert_equal "text/vnd.turbo-stream.html", response.media_type
    assert_select "turbo-stream[action=replace][target=ship-step] template turbo-frame#ship-step[target=_top]" do
      assert_select ".guide-do.just-done .guide-do-title", "rock is in review"
      assert_select "[data-controller=guide-step]"
    end
    assert_select "#ship-checks", 0
    assert @project.ships.sole.pending?

    get guide_ship_path
    assert_select "turbo-frame#ship-step .guide-do-title", "rock is in review"
    assert_select "#ship-step", text: /you can ship again once it's reviewed/
    assert_select ".just-done", 0
    get "/guide/publish"
    assert_select "turbo-frame#ship-step:not([src]) .guide-do-title", "rock is in review"
  end

  test "without JavaScript, a ship from the guide opens the guide at its Ship it step" do
    @project.update!(READY)
    post ship_project_path(@project), params: { from: "guide" }
    assert_redirected_to BACK
    assert_equal "shipped! your hours are pending review.", flash[:notice]
    assert @project.ships.sole.pending?
  end

  test "a ship blocked from the guide shows why in place, and without JavaScript goes back to the guide" do
    @project.update!(READY)
    @project.ships.create!(user: @user, claimed_seconds: 60)
    post ship_project_path(@project), params: { from: "guide" }, headers: STREAM
    assert_response :unprocessable_entity
    assert_select "#ship-checks .banner.alert", "not yet: your last ship needs its review first"
    assert_select ".requirements-note", 0

    post ship_project_path(@project), params: { from: "guide" }
    assert_redirected_to BACK
    assert_equal "not yet: your last ship needs its review first", flash[:alert]
    assert_equal 1, @project.ships.count
  end

  test "with no unshipped pet, the step shows the pet that shipped last: in review, then with new hours to ship again" do
    @project.update!(READY)
    ship = @project.ships.create!(user: @user, claimed_seconds: 60)
    get guide_ship_path
    assert_select "#ship-step .guide-do-title", "rock is in review"

    admin = User.create!(hca_id: "ident!guide-ship-admin", admin: true)
    ship.approve_review!(by: admin, seconds: 60, judgement: "ok", feedback: nil)
    ship.pass_fraud!(by: admin)
    get guide_ship_path
    assert_select "#ship-step .guide-do-title", "ship rock again"
    assert_select "#ship-step #ship-checks"
    assert_select "#ship-check-new_hours", 0

    # A new pet the guide is about comes first.
    @user.projects.create!(name: "pebble", hackatime_projects: [ "pebble" ])
    get guide_ship_path
    assert_select "#ship-step .guide-do-title", "ship pebble"
  end

  test "signed out, the step signs in and comes back to it" do
    delete logout_path
    get "/guide/publish"
    assert_select "#ship-step .guide-do-title", "ship your pet"
    assert_select "#ship-step input[name=origin][value=?]", "/guide/publish#ship-step"
    assert_select "#ship-checks", 0
  end

  test "an unverified participant's identity check links to verify it, and back to the guide's Ship it step" do
    user = log_in("unverified")
    post dev_hackatime_path
    user.projects.create!(name: "rock", hackatime_projects: [ "rock-pet" ])
    get guide_ship_path
    link = css_select("#ship-check-eligible a[target=_blank]").first
    assert_equal "verify it ↗", link.text
    assert_includes link["href"], CGI.escape("/guide/publish#ship")
  end

  test "the list's own page is as it was: its requirements line, its own way back, and no guide" do
    @project.update!(READY)
    get checks_project_path(@project)
    assert_select ".requirements-note", /read the submission requirements before you ship/
    assert_select "#ship-checks[data-ship-checks-url-value=?]", checks_project_path(@project)
    assert_select "#ship-checks input[name=from]", 0

    patch project_path(@project), params: { checks: 1, project: { description: "#{READY[:description]}!" } }
    assert_redirected_to checks_project_path(@project)
    post ship_project_path(@project)
    assert_redirected_to projects_path(anchor: "pet-#{@project.id}")
  end
end
