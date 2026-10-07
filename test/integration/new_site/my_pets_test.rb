require "test_helper"

# My pets: every pet a participant has, made with the guide or not, each a
# window holding all there is about the pet, as a pet has no page of its
# own. Each has one main thing to do next. With no pet, it says what a pet
# is and offers a new one and the guide.
class NewSiteMyPetsTest < ActionDispatch::IntegrationTest
  include NewSiteTests
  SHOTS = [ { "id" => "a", "key" => "a.png", "url" => "https://playground.hackclub-assets.com/a.png" },
            { "id" => "b", "key" => "b.png", "url" => "https://playground.hackclub-assets.com/b.png" } ].freeze

  test "each pet's window holds its screenshots, state, hours, links, Hackatime projects, ships, and one main action" do
    user = log_in("participant")
    # Tracked a moment ago, so the page asks Hackatime for nothing.
    rock = user.projects.create!(name: "rock", description: "naps on your taskbar", hackatime_projects: [ "rock" ],
                                 code_url: "https://github.com/pet/rock", playable_url: "https://pet.itch.io/rock",
                                 tracked_seconds: 3 * 3600, tracked_at: Time.current, screenshots: SHOTS)
    rock.ships.create!(user:, claimed_seconds: 2 * 3600, state: "approved", approved_seconds: 90 * 60, review_feedback: "lovely rock")
    goose = user.projects.create!(name: "goose", hackatime_projects: [ "goose" ], tracked_seconds: 3600, tracked_at: Time.current,
                                  screenshots: SHOTS.first(1))
    goose.ships.create!(user:, claimed_seconds: 3600)
    fluffy = user.projects.create!(name: "fluffy", tracked_at: Time.current)
    User.create!(hca_id: "ident!other", email: "other@example.com").projects.create!(name: "not mine")

    get projects_path
    assert_response :success
    assert_select "title", "my pets · playground"
    # The open tab names the page, so its heading is for screen readers.
    assert_select "h1.visually-hidden", "my pets"
    assert_select ".pet-list > li.pet-window", 3
    assert_select ".pet-title", text: "not mine", count: 0
    assert_select ".pet-list > li.pet-new:last-child a[href=?]", new_project_path, /new pet/
    # Nothing links to a page of the pet's own.
    [ rock, goose, fluffy ].each { assert_select "a[href=?]", project_path(it), 0 }

    assert_select "#pet-#{rock.id}" do
      assert_select ".pet-titlebar h2.pet-title", "rock"
      assert_select ".pet-titlebar .pet-marks"
      assert_select ".pet-shots .carousel img.shot", 2
      assert_select ".pet-state .badge", "approved"
      assert_select ".pet-description", "naps on your taskbar"
      assert_select ".pet-hours", /tracked 3h 0m · 1h 30m approved · 1h 0m unshipped/
      assert_select ".pet-links a[href='https://github.com/pet/rock'][target=_blank]", "code ↗"
      assert_select ".pet-links a[href='https://pet.itch.io/rock'][target=_blank]", "shipped link ↗"
      assert_select ".pet-hackatime", /Hackatime: rock/
      assert_select ".pet-ships li", 1
      assert_select ".pet-ships li", /#1\s+approved/
      assert_select ".pet-ships blockquote", "lovely rock"
      assert_select ".pet-actions a.btn.primary[href=?]", ship_project_path(rock), "ship again"
      assert_select ".pet-actions a[href=?]", edit_project_path(rock), "edit"
    end

    # A ship in review leaves nothing to do but wait.
    assert_select "#pet-#{goose.id}" do
      assert_select ".pet-shots > img.shot[src=?]", SHOTS.first["url"]
      assert_select ".pet-state .badge", "pending"
      assert_select ".pet-hours", /tracked 1h 0m · 1h 0m pending\s*\z/
      assert_select ".pet-actions .pet-waiting", "in review"
      assert_select ".pet-actions a.btn", 0
    end

    # A pet with no screenshot has a place for one, and says why no hours count.
    assert_select "#pet-#{fluffy.id}" do
      assert_select "a.pet-shots-empty[href=?]", edit_project_path(fluffy), /no screenshot yet/
      assert_select ".pet-state .badge", "not shipped"
      assert_select ".pet-hours", /no hours yet/
      assert_select ".pet-links", 0
      assert_select ".pet-hackatime", /no Hackatime project linked/
      assert_select ".pet-ships", 0
      assert_select ".pet-actions a.btn.primary[href=?]", ship_project_path(fluffy), "ship it"
    end
  end

  test "with no pets, my pets says what a pet is, and offers a new pet and the guide" do
    log_in("newbie")
    get projects_path
    assert_response :success
    assert_select ".pet-list", 0
    assert_select ".pets-empty .pet-title", "no pets yet"
    assert_select ".pets-empty p", /any language or engine/
    assert_select ".pets-empty a.btn[href=?]", new_project_path, "+ new pet"
    assert_select ".pets-empty a[href=?]", guide_path, "follow the guide"
  end

  test "an old link to a pet lands on its window, and saving or making a pet does too" do
    user = log_in("participant")
    rock = user.projects.create!(name: "rock")
    card = projects_path(anchor: "pet-#{rock.id}")
    get project_path(rock)
    assert_redirected_to card

    get edit_project_path(rock)
    assert_select "a[href=?]", card, "← my pets"
    assert_select "form a.btn[href=?]", card, "cancel"
    patch project_path(rock), params: { project: { description: "naps" } }
    assert_redirected_to card

    get new_project_path
    assert_select "a[href=?]", projects_path, "← my pets"
    assert_select "form a.btn[href=?]", projects_path, "cancel"
    post projects_path, params: { project: { name: "goose" } }
    assert_redirected_to projects_path(anchor: "pet-#{user.projects.find_by!(name: "goose").id}")
  end

  test "a message on its way through an old link to a pet still shows on the pet's window" do
    user = log_in("participant")
    rock = user.projects.create!(name: "rock")
    rock.ships.create!(user:)
    delete project_path(rock)
    get project_path(rock)
    follow_redirect!
    assert_select ".flash.alert", "a shipped pet cannot be deleted"
  end

  test "with two pets or more, the active pet is marked, and each other pet can be made active from its window" do
    user = log_in("participant")
    rock = user.projects.create!(name: "rock", tracked_at: Time.current)
    get projects_path
    assert_select ".pet-mark", 0, "one pet needs no mark"
    assert_select ".pet-make-active", 0

    # With none set, the guide's own choice is active: the newest pet that never shipped.
    goose = user.projects.create!(name: "goose", tracked_at: Time.current)
    get projects_path
    assert_select "#pet-#{goose.id} .pet-titlebar .pet-mark", /\Aactive/
    assert_select "#pet-#{goose.id} .pet-make-active", 0
    assert_select "#pet-#{rock.id} .pet-mark", 0
    assert_select "#pet-#{rock.id} .pet-titlebar form[action=?]", active_pet_path do
      assert_select "input[name=_method][value=patch]"
      assert_select "input[name=pet_id][value=?]", rock.id.to_s
      assert_select "input[name=from][value=pets]"
      assert_select "button.pet-make-active[aria-label=?]", "make rock your active pet", "make active"
    end

    patch active_pet_path, params: { pet_id: rock.id, from: "pets" }
    assert_redirected_to projects_path(anchor: "pet-#{rock.id}")
    follow_redirect!
    assert_select "#pet-#{rock.id} .pet-mark", /\Aactive/
    assert_select "#pet-#{goose.id} .pet-make-active", "make active"
  end

  test "signed out, my pets goes to the login" do
    get projects_path
    assert_redirected_to login_path
  end
end
