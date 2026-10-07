require "test_helper"

# The new site's pages, for a participant with the new site on, held to what
# the desktop site's pages are held to: no link preview tags behind the login,
# no program words, and no Turbo preview on a page with fields. A new or
# saved pet lands on its card on my pets, whose hours count only the program
# window's time.
class NewSitePagesTest < ActionDispatch::IntegrationTest
  include NewSiteTests

  TAGS = "meta[property^='og:'], meta[name^='twitter:'], meta[name='description'], meta[name='theme-color']".freeze
  NO_PREVIEW = "meta[name='turbo-cache-control'][content='no-preview']".freeze

  test "pages behind the login carry no tags and show nothing from the account in the head" do
    user = log_in("participant")
    pet = user.projects.create!(name: "Secret Pet Name", description: "a secret description")
    [ root_path, guide_path, guide_page_path("move"), projects_path, edit_project_path(pet), ship_project_path(pet),
      checks_project_path(pet), delete_project_path(pet), new_project_path, requirements_path ].each do |path|
      get path
      assert_response :ok, path
      assert_select "body.new-site", 1, path
      assert_select TAGS, 0, path
      # A pet's own pages name it in the title, which no unfurl sees: signed
      # out, they go to the login.
      head = css_select("head").to_s.sub(%r{<title>.*?</title>}m, "")
      [ pet.name, pet.description, user.display_name, user.email ].each { assert_not_includes head, it, path }
    end
  end

  test "no page says ysws, verified or not" do
    user = log_in("unverified")
    project = user.projects.create!(name: "rock")
    [ root_path, guide_path, guide_page_path("move"), guide_page_path("publish"), projects_path, new_project_path, edit_project_path(project),
      ship_project_path(project), delete_project_path(project), checks_project_path(project), requirements_path ].each do |path|
      get path
      assert_response :success, path
      assert_no_match(/\bysws\b/i, response.body, path)
    end
    get ship_project_path(project)
    assert_select "#ship-check-eligible", /your identity needs to be verified, and your account eligible/
  end

  test "the pages with fields keep out of Turbo's preview, and the others keep it" do
    project = log_in("participant").projects.create!(name: "rock")
    [ new_project_path, edit_project_path(project), ship_project_path(project), checks_project_path(project) ].each do |path|
      get path
      assert_select NO_PREVIEW, 1, path
    end
    [ projects_path, delete_project_path(project), guide_path ].each do |path|
      get path
      assert_select NO_PREVIEW, 0, path
    end
  end

  test "a new pet and a saved one land on the pet's card on my pets, whose ship page lists what is left" do
    user = log_in("participant")
    post dev_hackatime_path
    post projects_path, params: { project: { name: "rock", description: "a rock that walks along your taskbar" } }
    project = user.projects.sole
    assert_redirected_to projects_path(anchor: "pet-#{project.id}")
    follow_redirect!
    assert_select "#pet-#{project.id} a[href=?]", ship_project_path(project), "ship it"
    assert_select "input[type=file], .shots-grid, [data-controller~='screenshot-upload']", 0, "my pets has nothing to upload with"

    patch project_path(project), params: { project: { code_url: "https://github.com/pet/rock" } }
    assert_redirected_to projects_path(anchor: "pet-#{project.id}")

    get ship_project_path(project)
    assert_select ".checks li", text: /your pet needs a Hackatime project/ do
      assert_select "input[type=checkbox][name='project[hackatime_projects][]'][value='rock-pet']"
    end
  end

  test "the shipped link asks for the pet's itch.io page, on the edit page and in the ship list" do
    project = log_in("participant").projects.create!(name: "rock", description: "a rock that walks along your taskbar",
                                                     hackatime_projects: [ "rock-pet" ])
    get edit_project_path(project)
    assert_select "label", text: /shipped link\s+your pet's itch.io page/ do
      assert_select "input[placeholder='https://you.itch.io/your-pet']"
    end
    get ship_project_path(project)
    assert_select "#ship-tip-playable_url", NewSiteHelper::PLAYABLE_TIP
    assert_select "input[name='project[playable_url]'][placeholder='https://you.itch.io/your-pet']"
  end

  test "a pet's card counts only the program window's time" do
    window = ProgramWindow.load({ starts_at: "2026-09-25 17:00", ends_at: "2026-10-09 17:00" })
    ProgramWindow.current = window
    travel_to window.starts_at - 1.minute
    user = log_in("participant")
    post dev_hackatime_path
    pet = user.projects.create!(name: "rock", hackatime_projects: %w[rock-pet rock-pet-art])
    get projects_path
    assert_select "#pet-#{pet.id} .pet-hours", /no hours yet/

    travel_to window.starts_at + 1.hour
    get projects_path
    assert_select "#pet-#{pet.id} .pet-hours", /tracked 55m · 55m unshipped/
  end
end
