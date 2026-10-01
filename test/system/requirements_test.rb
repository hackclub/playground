require "application_system_test_case"

# The submission requirements in a real browser: requirements.txt opens them
# on the desktop, and the ship list points to them.
class RequirementsSystemTest < ApplicationSystemTestCase
  test "requirements.txt opens the requirements in a window of its own" do
    forget_open_windows
    visit root_path
    close_login_window
    find(".app", exact_text: "requirements.txt").send_keys(:enter)
    within_frame(find("#window-requirements\\.txt iframe")) do
      assert_selector "h1", text: "submission requirements"
      assert_selector ".requirements-list li", count: 9
      assert_no_link "← desktop"
    end
    within("#window-requirements\\.txt .windowheader") { click_button "close", enable_aria_label: true }
    assert_no_selector "#window-requirements\\.txt"
  end

  test "the ship list's link opens requirements.txt on the desktop" do
    user = log_in_as("participant")
    user.update!(hackatime_access_token: "fake")
    project = user.projects.create!(name: "rock")
    visit root_path(open: "goal")
    within_frame(find(".ship-frame")) { find_link(project.name, exact_text: true).send_keys(:enter) }
    within_frame(find("#window-pet-#{project.id} iframe")) { click_link "ship" }
    within_frame(find("#window-ship-#{project.id} iframe")) { click_link "submission requirements" }
    within_frame(find("#window-requirements\\.txt iframe")) { assert_selector "h1", text: "submission requirements" }
    assert_selector "#window-ship-#{project.id}"
  end
end
