require "test_helper"

# The landing, and the guide with its own steps: sign in, link Hackatime,
# pick the pet's project from Hackatime's list, the folder's name after the
# sync, and ship. A login begun at a step comes back to it, on the page of
# the guide's step that holds it.
class NewSiteGuideStepsTest < ActionDispatch::IntegrationTest
  include NewSiteTests
  teardown { FileUtils.rm_rf(FakeHeartbeats.dir) }

  test "the landing shows pets, prizes with a link to the requirements, what to do now, and the FAQ" do
    get root_path
    assert_select ".home-say", "Make a cool desktop pet like these"
    assert_select ".home-examples li", 4
    assert_select ".home-prizes .home-goals li", 3
    assert_select ".home-prizes .requirements-list", 0
    assert_select ".home-prizes .home-requirements a[href=?][target=_blank]", requirements_path
    assert_select ".home-now h2", "What do I do now?"
    assert_select ".home-steps li", 4
    assert_select ".home-now a.btn[href=?]", guide_path, text: "start the guide →"
    assert_select ".home-sponsor a", "Armand"
    assert_select ".topbar", 0
    # The FAQ follows the steps, and the guide lives on its own page.
    assert_select ".home-now ~ .home-faq h2", "FAQ"
    assert_select ".home-faq details summary", 4
    assert_select ".home-faq details[open]", 0
    assert_select "article#guide", 0
  end

  test "signed out, the guide's sign in step is one button that comes back to the step" do
    get guide_path
    assert_select "#sign-in-title", "Sign in"
    assert_select "#sign-in form[action='/dev/login'] input[name=origin][value=?]", "/guide/setup#sign-in"
    assert_select ".hub-side", 0

    get dev_login_path(as: "newbie", origin: "/guide/setup#sign-in")
    assert_redirected_to "/guide/setup#sign-in"
  end

  test "signed out, the pick and ship steps each sign in and come back to their own step's page" do
    get guide_check_path(frame: "pick-step")
    assert_select "input[name=origin][value=?]", "/guide/scene#pick-project"
    get "/guide/publish"
    assert_select "#ship-step input[name=origin][value=?]", "/guide/publish#ship-step"

    get dev_login_path(as: "newbie", origin: "/guide/scene#pick-project")
    assert_redirected_to "/guide/scene#pick-project"
  end

  test "a way back from before the steps goes to the step that holds its anchor" do
    { "/guide#sign-in" => "/guide/setup#sign-in", "/guide#pick-step" => "/guide/scene#pick-step",
      "/guide#ship-step" => "/guide/publish#ship-step",
      # Hackatime is connected at the pick step now, so its old parts go there.
      "/guide#hackatime-step" => "/guide/scene#pick-step", "/guide/setup#hackatime-step" => "/guide/scene#pick-step",
      "/guide/setup#connect-hackatime" => "/guide/scene#pick-project" }.each do |old, now|
      assert_equal now, GuidePage.way_back(old), old
    end
    # An anchor no step holds stays on /guide, which shows the first step.
    assert_equal "/guide#gone", GuidePage.way_back("/guide#gone")
    get dev_login_path(as: "newbie", origin: "/guide#pick-step")
    assert_redirected_to "/guide/scene#pick-step"
  end

  test "a way back that is not a guide step is ignored" do
    get dev_login_path(as: "newbie", origin: "https://example.com/guide#sign-in")
    assert_redirected_to hackatime_step_path
    [ "/guide/nope#sign-in", "/guide/move", "/guide", "/guidebook#sign-in", "/guide/move#Pick", "//evil.example/guide#x" ].each do |origin|
      assert_nil GuidePage.way_back(origin), origin
    end
  end

  test "signed in, the guide has the next step beside it, and the dashboard goes to the guide" do
    log_in("newbie")
    get guide_path
    assert_select "#hub-next #next-title", "start the guide"
    assert_select "#sign-in-title", 0
    assert_select "#sign-in", 0
    assert_select ".guide-step h2:first-of-type#setup-godot"
    get dashboard_path
    assert_redirected_to guide_path
  end

  test "the pick step has its own heading at the end of Build the scene, with the frame under it" do
    get "/guide/scene"
    assert_select ".guide-step > section[aria-labelledby=transparent] + section[aria-labelledby=pick-project]:last-child > h2#pick-project",
                  "Pick your pet's project"
    assert_select "section[aria-labelledby=pick-project] > turbo-frame#pick-step[src=?]", guide_check_path(frame: "pick-step")
    assert_select "section[aria-labelledby=transparent] turbo-frame", 0
    get "/guide/move"
    assert_select "#pick-project, turbo-frame#pick-step", 0
  end

  test "the next step card links to the guide step that holds its part, at that part" do
    user = log_in("newbie")
    hrefs = []
    card = lambda do
      get guide_path
      [ css_select("#hub-next #next-title").first.text, css_select("#hub-next a.btn").first.then { [ it["href"], it.text ] } ]
    end
    # On the guide, each link says where it goes, and none says back to the guide.
    assert_equal [ "start the guide", [ "/guide/setup#setup-godot", "go to: Set up Godot" ] ], card.call
    post dev_hackatime_path
    assert_equal [ "pick your pet's project", [ "/guide/scene#pick-project", "go to: Pick your pet's project" ] ], card.call
    # A pet whose Hackatime project has no time yet is not counting hours, so
    # its next step is back at the pick, and says why.
    user.projects.create!(name: "Fluffy", hackatime_projects: [ "Fluffy" ])
    assert_equal [ "link Fluffy to Hackatime", [ "/guide/scene#pick-project", "go to: Pick your pet's project" ] ], card.call
    assert_select "#hub-next p", "Hackatime counts no time on Fluffy yet. pick the project Godot sends its time to, so its hours count."
    # Once Hackatime counts its time, the guide goes on from the step after the pick.
    FakeHeartbeats.start(user, "Fluffy")
    travel 6.minutes
    assert_equal [ "keep building Fluffy", [ "/guide/art", "continue: Art and script" ] ], card.call
    assert_no_match(/back to the guide/, response.body)

    [ "/guide/setup#setup-godot", "/guide/scene#pick-project" ].each do |href|
      path, anchor = href.split("#")
      get path
      assert_select "article.guide ##{anchor}", 1, href
    end
    # The card links the other parts it may point to, each on its step.
    { "pick-project" => "/guide/scene", "ship" => "/guide/publish", "your-own" => "/guide/own" }.each do |anchor, path|
      assert_equal "#{path}##{anchor}", GuidePage.href(anchor)
    end
  end

  test "the next step card follows the pet the ship step is about: in review after a ship, then ship it again with new hours" do
    freeze_time
    user = log_in("newbie")
    post dev_hackatime_path
    FakeHeartbeats.start(user, "rock")
    pet = user.projects.create!(name: "rock", hackatime_projects: [ "rock" ], description: "a rock that walks along your taskbar",
                                code_url: "https://github.com/pet/rock", playable_url: "https://pet.itch.io/rock",
                                ship_message_url: "https://hackclub.slack.com/archives/C0C51NCK1DG/p1759012345678901",
                                screenshots: [ { "id" => "shot", "key" => "shot.webp", "url" => "https://playground.hackclub-assets.com/shot.webp" } ])
    card = lambda do
      get guide_path
      [ css_select("#hub-next #next-title").first.text, css_select("#hub-next a.btn").first["href"] ]
    end
    assert_equal [ "keep building rock", "/guide/art" ], card.call

    # A ship from the guide: the pet has no unshipped sibling, so the card
    # stays on it, and its frame beside the guide says so when it reloads.
    post ship_project_path(pet), params: { from: "guide" }
    assert_redirected_to "/guide/publish#ship"
    ship = pet.ships.sole
    assert ship.pending?
    assert_equal [ "rock is in review", "/guide/own#your-own" ], card.call
    get guide_side_path(part: "next")
    assert_select "#hub-next #next-title", "rock is in review"

    # Reviewed, with no hours since the ship, there is nothing to ship.
    admin = User.create!(hca_id: "ident!next-step-admin", admin: true)
    ship.approve_review!(by: admin, seconds: ship.claimed_seconds, judgement: "ok", feedback: nil)
    ship.pass_fraud!(by: admin)
    assert_equal [ "keep building rock", "/guide/art" ], card.call

    # An hour of coding later, the card offers to ship those hours.
    travel 1.hour
    assert_equal [ "ship rock again", "/guide/publish#ship" ], card.call
    assert_select "#hub-next p", "1h 0m since its last ship. ship to get them reviewed."

    # A prize to redeem still comes first, and a Hackatime link to fix before that.
    ship.update!(approved_seconds: Goal.all.first.seconds)
    assert_equal "redeem your #{Goal.all.first.name}", card.call.first
    travel 10.minutes
    user.update!(hackatime_access_token: "revoked")
    assert_equal "connect Hackatime again", card.call.first

    # A ship keeps the guide on the pet that shipped, until a new pet, which
    # becomes the active pet, comes first, as on the ship step.
    user.update!(hackatime_access_token: "fake")
    ship.update!(approved_seconds: ship.claimed_seconds)
    user.projects.create!(name: "pebble")
    assert_equal "ship rock again", card.call.first
    post projects_path, params: { project: { name: "twig" } }
    assert_equal [ "link twig to Hackatime", "/guide/scene#pick-project" ], card.call
  end

  test "the pick step, after Movement, links Hackatime, lists Hackatime's projects, and a pick makes the pet" do
    user = log_in("newbie")
    get guide_check_path(frame: "pick-step")
    # The pick step has its own heading, so its title is not said again.
    assert_select "#pick-step .guide-do-title", 0
    assert_select "#pick-step .guide-do p", "connect Hackatime to pick your pet's project."
    assert_select "#pick-step .guide-do .btn", /\Aconnect Hackatime/

    post dev_hackatime_path, params: { origin: "/guide/scene#pick-project" }
    assert_redirected_to "/guide/scene#pick-project"
    get guide_check_path(frame: "pick-step")
    assert_select ".guide-do-waiting"
    assert_select "#pick-step .guide-do-title", 0

    FakeHeartbeats.start(user, "dotfiles")
    FakeHeartbeats.start(user, "My very cool pet")
    get guide_check_path(frame: "pick-step")
    assert_select ".guide-do-pick li", 2
    assert_select "#pick-step .guide-do-title", "which one is your pet?"

    post guide_link_path, params: { name: "not-listed", frame: "pick-step" }
    assert_empty user.projects

    post guide_link_path, params: { name: "My very cool pet", frame: "pick-step" }
    follow_redirect!
    assert_select ".guide-do.done.just-done .guide-do-title", /\AHackatime counts My very cool pet/
    pet = user.projects.sole
    assert_equal [ "My very cool pet", [ "My very cool pet" ] ], [ pet.name, pet.hackatime_projects ]
  end

  test "a pet takes the name of its first Hackatime project, and a second leaves the name alone" do
    user = log_in("newbie")
    post dev_hackatime_path
    pet = user.projects.create!(name: "untitled")
    FakeHeartbeats.start(user, "My very cool pet")
    FakeHeartbeats.start(user, "my-very-cool-pet")

    post guide_link_path, params: { name: "My very cool pet", frame: "pick-step" }
    assert_equal [ "My very cool pet", [ "My very cool pet" ] ], [ pet.reload.name, pet.hackatime_projects ]
    post guide_link_path, params: { name: "my-very-cool-pet", frame: "pick-step" }
    assert_equal "My very cool pet", pet.reload.name
  end

  test "the side column shows the hours and no pets, which have their own page, and asks for nothing but the next step" do
    user = log_in("newbie")
    get guide_side_path
    assert_select "#hours-title", "your hours"
    assert_select "#hub-side .banner", 0
    user.projects.create!(name: "Fluffy")
    get guide_side_path
    assert_select "#hours-title", "your hours"
    assert_select "#hub-side", text: /Fluffy/, count: 0
    assert_select "#hub-side a[href=?]", new_project_path, 0
  end

  test "once the pet counts, the pick step offers the folder's name for the same pet" do
    user = log_in("newbie")
    post dev_hackatime_path
    pet = user.projects.create!(name: "Fluffy", hackatime_projects: [ "Fluffy" ])
    FakeHeartbeats.start(user, "Fluffy")
    FakeHeartbeats.start(user, "fluffy-folder")

    get guide_check_path(frame: "pick-step")
    assert_select "#pick-step .guide-do.done .guide-do-title", /\AHackatime counts Fluffy/
    assert_select "#pick-step form[action=?] input[name=name][value=?]", guide_link_path, "fluffy-folder"

    post guide_link_path, params: { name: "fluffy-folder", frame: "pick-step" }
    assert_redirected_to guide_check_path(frame: "pick-step")
    assert_equal [ "Fluffy", "fluffy-folder" ], pet.reload.hackatime_projects
  end

  test "with no pet, the ship step links to the pick step on its own step's page" do
    log_in("newbie")
    get guide_ship_path
    assert_select "#ship-step a[href=?]", "/guide/scene#pick-project", "pick your pet's Hackatime project"
  end

  test "the pick step's Hackatime button comes back to the pick step, and the next step card sends there to connect" do
    user = log_in("newbie")
    get guide_check_path(frame: "pick-step")
    assert_select "input[name=origin][value=?]", "/guide/scene#pick-project"
    # The connect step is gone, so a request for its frame gets the pick step.
    get guide_check_path(frame: "hackatime-step")
    assert_select "turbo-frame#pick-step input[name=origin][value=?]", "/guide/scene#pick-project"
    get "/guide/setup"
    assert_select "#connect-hackatime, article.guide turbo-frame", 0

    user.projects.create!(name: "Fluffy")
    get guide_side_path(part: "next")
    assert_select "#hub-next #next-title", "connect Hackatime"
    assert_select "#hub-next a.btn[href=?]", "/guide/scene#pick-project"
  end

  test "the pick step asks to connect Hackatime again when Hackatime refuses its link, and says when Hackatime banned the account" do
    user = log_in("newbie")
    post dev_hackatime_path
    user.update!(hackatime_access_token: "revoked")
    get guide_check_path(frame: "pick-step")
    assert_select "#pick-step .guide-do-title", "connect Hackatime again"
    assert_select "#pick-step .banner.alert", Hackatime::UNLINKED
    assert_select "#pick-step input[name=origin][value=?]", "/guide/scene#pick-project"

    user.update!(hackatime_access_token: "fake", hackatime_trust_level: "red")
    get guide_check_path(frame: "pick-step")
    assert_select "#pick-step .banner.alert", "Hackatime has banned this account, so its hours cannot count."
  end

  test "the ship step holds the guide's pet's ship list, with only what still blocks it" do
    user = log_in("newbie")
    user.projects.create!(name: "Fluffy", hackatime_projects: [ "Fluffy" ], description: "a rock that rolls around")
    get guide_ship_path
    assert_select "#ship-step .guide-do-title", "ship Fluffy"
    assert_select "#ship-step #ship-check-screenshot.todo", /your pet needs a screenshot/
    assert_select "#ship-step #ship-check-description", 0
  end
end

# The same way back through the real OAuth strategies, in OmniAuth's test mode.
class NewSiteGuideStepsOAuthTest < ActionDispatch::IntegrationTest
  include NewSiteTests
  setup do
    OmniAuth.config.test_mode = true
    ENV["REAL_SERVICES"] = "1"
    OmniAuth.config.mock_auth[:hack_club] = OmniAuth::AuthHash.new(
      provider: "hack_club", uid: "ident!guide", credentials: { token: "hca-guide" },
      extra: { raw_info: { identity: { id: "ident!guide", primary_email: "guide@example.com", first_name: "Sam", last_name: "Dev", verification_status: "verified", ysws_eligible: true } } }
    )
    OmniAuth.config.mock_auth[:hackatime] = OmniAuth::AuthHash.new(provider: "hackatime", credentials: { token: "hka-guide" })
    # The account that logs in has the new site on, so its login goes back to the new guide.
    User.create!(hca_id: "ident!guide", new_site: true)
  end

  teardown do
    OmniAuth.config.test_mode = false
    OmniAuth.config.mock_auth.delete(:hack_club)
    OmniAuth.config.mock_auth.delete(:hackatime)
    ENV.delete("REAL_SERVICES")
  end

  test "Hack Club and Hackatime both go back to the guide step they began at, and the login skips its Hackatime step" do
    post "/auth/hack_club", params: { origin: "/guide/setup#sign-in" }
    follow_redirect!
    assert_redirected_to "/guide/setup#sign-in"

    post "/auth/hackatime", params: { origin: "/guide/scene#pick-step" }
    follow_redirect!
    assert_redirected_to "/guide/scene#pick-step"
    assert_equal "hka-guide", User.find_by!(hca_id: "ident!guide").hackatime_access_token
  end

  test "a login begun on the one long page the guide was goes back to the step that holds its anchor" do
    post "/auth/hack_club", params: { origin: "/guide#sign-in" }
    follow_redirect!
    assert_redirected_to "/guide/setup#sign-in"

    post "/auth/hackatime", params: { origin: "/guide#hackatime-step" }
    follow_redirect!
    assert_redirected_to "/guide/scene#pick-step"
  end

  test "a login from anywhere else goes on as before" do
    post "/auth/hack_club", params: { origin: "/elsewhere" }
    follow_redirect!
    assert_redirected_to hackatime_step_path
  end
end
