require "test_helper"

# Hackatime's last-project placeholder is not a project: it is not listed
# in any picker, a form cannot link it, and it counts no hours. The fake
# Hackatime lists it, as the real one does.
class LastProjectTest < ActionDispatch::IntegrationTest
  include NewSiteTests
  LAST = Hackatime::IGNORED_PROJECTS.first
  WINDOW = ProgramWindow.load({ starts_at: "2026-09-25 17:00", ends_at: "2026-10-09 17:00" })
  STREAM = { "Accept" => "text/vnd.turbo-stream.html, text/html, application/xhtml+xml" }.freeze

  setup { ProgramWindow.current = WINDOW }
  teardown { FileUtils.rm_rf(FakeHeartbeats.dir) }

  def picker_names = css_select("ul.picker li strong").map(&:text)

  test "the edit form and the ship checklist list other projects but not the placeholder, and a save cannot link it" do
    travel_to WINDOW.ends_at - 1.minute
    user = log_in("participant")
    post dev_hackatime_path
    pet = user.projects.create!(name: "rock", hackatime_projects: [ "rock-pet" ])
    pet.update_columns(hackatime_projects: [ "rock-pet", LAST ]) # an old row

    get edit_project_path(pet)
    assert_response :success
    assert_includes picker_names, "frog-widget"
    assert_not_includes picker_names, LAST
    assert_not_includes response.body, "LAST_PROJECT"

    get checks_project_path(pet, shown: [ "hackatime_projects" ]), headers: STREAM
    assert_not_includes response.body, "LAST_PROJECT"

    patch project_path(pet), params: { project: { name: "rock", hackatime_projects: [ "", "rock-pet", LAST ] } }
    assert_equal [ "rock-pet" ], pet.reload.hackatime_projects
    assert_equal [ "rock-pet" ], pet.read_attribute(:hackatime_projects)

    get project_path(pet)
    assert_not_includes response.body, "LAST_PROJECT"
    get projects_path
    assert_not_includes response.body, "LAST_PROJECT"
  end

  test "a new pet's picker in the checks leaves the placeholder out and a pet made with it links nothing" do
    travel_to WINDOW.ends_at - 1.minute
    user = log_in("participant")
    post dev_hackatime_path
    post projects_path, params: { project: { name: "twig", hackatime_projects: [ "", LAST ] } }
    pet = user.projects.find_by!(name: "twig")
    assert_empty pet.read_attribute(:hackatime_projects)
    get checks_project_path(pet)
    assert_not_includes response.body, "LAST_PROJECT"
  end

  test "the guide's pick step does not list the placeholder, and a pick of it makes no pet" do
    user = log_in("newbie")
    post dev_hackatime_path, params: { origin: "/guide/setup#hackatime-step" }
    FakeHeartbeats.start(user, LAST)
    FakeHeartbeats.start(user, "My very cool pet")
    get guide_check_path(frame: "pick-step")
    assert_select ".guide-do-pick li", 1
    assert_not_includes response.body, "LAST_PROJECT"

    post guide_link_path, params: { name: LAST, frame: "pick-step" }
    assert_empty user.projects
  end

  test "a pet whose row holds the placeholder counts no hours on it" do
    travel_to WINDOW.ends_at - 1.minute
    user = log_in("participant")
    post dev_hackatime_path
    pet = user.projects.create!(name: "rock")
    pet.update_columns(hackatime_projects: [ LAST ])
    TrackedTime.refresh(pet, force: true)
    assert_equal 0, pet.reload.tracked_seconds

    pet.update_columns(hackatime_projects: [ "rock-pet", LAST ])
    TrackedTime.refresh(pet, force: true)
    alone = Hackatime.for(user).stats([ "rock-pet" ]).total_seconds
    assert_equal alone, pet.reload.tracked_seconds
    assert_equal alone, pet.unshipped_seconds
  end
end
