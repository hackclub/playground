require "test_helper"

# What the desktop asks the server for: a participant's pets as icons, the
# trash that follows their account, and the delete popups for a pet dragged
# into the trash, which delete it and answer without leaving the page.
class DesktopPetsTest < ActionDispatch::IntegrationTest
  setup { NewSite.for_visitors = false }
  teardown { NewSite.for_visitors = true }

  test "the desktop lists a signed-in participant's pets and trash, and nothing for a visitor" do
    get root_path
    assert_select "#apps[data-pets]", 0
    assert_select "#apps[data-trash]", 0
    assert_select "#apps[data-account]", 0

    user = log_in("participant")
    rock = user.projects.create!(name: "rock <b>", screenshots: [ { "id" => "rock", "key" => "rock.png", "url" => "https://playground.hackclub-assets.com/rock.png" } ])
    goose = user.projects.create!(name: "goose")
    User.create!(hca_id: "ident!other", email: "other@example.com").projects.create!(name: "not mine")
    user.update!(desktop_trash: [ "guide.txt" ])
    get root_path
    pets = JSON.parse(css_select("#apps").first["data-pets"])
    assert_equal [ { "id" => rock.id, "name" => "rock <b>" }, { "id" => goose.id, "name" => "goose" } ], pets
    # The banana peel is in the trash unless the participant took it out.
    assert_equal [ "banana peel", "guide.txt" ], JSON.parse(css_select("#apps").first["data-trash"])
    assert_equal [ "guide.txt" ], user.reload.desktop_trash
    user.update!(banana_peel_out: true)
    get root_path
    assert_equal [ "guide.txt" ], JSON.parse(css_select("#apps").first["data-trash"])
    # The account the desktop saves its open windows for, in the browser.
    assert_equal user.id.to_s, css_select("#apps").first["data-account"]

    get projects_path, as: :json
    assert_equal pets, response.parsed_body
    get projects_path
    assert_redirected_to dashboard_path
  end

  test "the trash saves a short list of icon names for the account, and nothing for a visitor" do
    patch trash_path, params: { icons: [ "welcome.txt" ] }, as: :json
    assert_response :unauthorized

    user = log_in("participant")
    patch trash_path, params: { icons: [ "welcome.txt", "welcome.txt", "", "x" * 65, "Hack Club" ] }, as: :json
    assert_response :no_content
    assert_equal [ "welcome.txt", "Hack Club" ], user.reload.desktop_trash
    patch trash_path, params: { icons: [] }, as: :json
    assert_equal [], user.reload.desktop_trash
    patch trash_path, params: { icons: (1..40).map { "icon #{it}" } }, as: :json
    assert_equal 32, user.reload.desktop_trash.size
  end

  test "the trash records the banana peel as out when it comes out, and in when it goes back" do
    user = log_in("participant")
    assert_not user.banana_peel_out
    patch trash_path, params: { icons: [], banana_peel_out: true }, as: :json
    assert user.reload.banana_peel_out
    # A change to the rest of the trash leaves the record alone.
    patch trash_path, params: { icons: [ "guide.txt" ] }, as: :json
    assert user.reload.banana_peel_out
    patch trash_path, params: { icons: [ "guide.txt", "banana peel" ], banana_peel_out: false }, as: :json
    assert_equal [ [ "guide.txt", "banana peel" ], false ], [ user.reload.desktop_trash, user.banana_peel_out ]
  end

  test "a pet's trash page holds its three delete popups, open for the desktop, and a shipped pet's holds one that says no" do
    user = log_in("participant")
    rock = user.projects.create!(name: "rock")
    get trash_project_path(rock)
    assert_response :success
    assert_select "body.popups-only"
    assert_select "[data-controller=delete-confirm][data-delete-confirm-desktop-value=true][data-delete-confirm-project-value='#{rock.id}']"
    assert_select "dialog.popup[role=alertdialog]", 3
    assert_select "form.button_to[action='#{project_path(rock)}'] button[hidden]", "delete pet"
    assert_select ".flash", 0

    shipped = user.projects.create!(name: "goose")
    shipped.ships.create!(user: user)
    get trash_project_path(shipped)
    assert_select "dialog.popup", 1
    assert_select "dialog.popup p", "a shipped pet cannot be deleted"
    assert_select "dialog.popup .popup-buttons button", 1
    assert_select "form", 0
  end

  test "the desktop's rename answers in JSON with the pet's icon, or with the edit page's error, and leaves others' pets alone" do
    user = log_in("participant")
    rock = user.projects.create!(name: "rock", description: "naps")
    patch project_path(rock), params: { project: { name: "pebble <b>" } }, as: :json
    assert_response :success
    assert_equal({ "id" => rock.id, "name" => "pebble <b>" }, response.parsed_body)
    assert_equal [ "pebble <b>", "naps" ], rock.reload.values_at(:name, :description)

    [ [ "", "Name can't be blank" ], [ "x" * 81, "Name is too long (maximum is 80 characters)" ] ].each do |name, error|
      patch project_path(rock), params: { project: { name: } }, as: :json
      assert_response :unprocessable_entity
      assert_equal({ "error" => error }, response.parsed_body)
      assert_equal "pebble <b>", rock.reload.name
    end

    # A shipped pet keeps its edit page, so it can be renamed too.
    rock.ships.create!(user:)
    patch project_path(rock), params: { project: { name: "boulder" } }, as: :json
    assert_equal "boulder", rock.reload.name

    other = User.create!(hca_id: "ident!other", email: "other@example.com").projects.create!(name: "not mine")
    patch project_path(other), params: { project: { name: "mine now" } }, as: :json
    assert_response :not_found
    assert_equal "not mine", other.reload.name
  end

  test "the desktop's delete answers in JSON, and a shipped pet stays" do
    user = log_in("participant")
    rock = user.projects.create!(name: "rock")
    delete project_path(rock), as: :json
    assert_response :no_content
    assert_not Project.exists?(rock.id)

    shipped = user.projects.create!(name: "goose")
    shipped.ships.create!(user: user)
    delete project_path(shipped), as: :json
    assert_response :unprocessable_entity
    assert Project.exists?(shipped.id)
  end
end
