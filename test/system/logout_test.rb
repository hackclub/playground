require "application_system_test_case"

# The server holds a pet list asked for with hold=1 until the test lets it go.
module HoldPetList
  mattr_accessor :arrived, :release

  def index
    if params[:hold] && HoldPetList.release
      HoldPetList.arrived << true
      HoldPetList.release.pop
    end
    super
  end
end
ProjectsController.prepend(HoldPetList)

# A log out ends the login for good. Every response sets the session cookie
# again, so an answer still on its way when the participant logs out brings
# the old cookie back. It must not sign them back in.
class LogoutTest < ApplicationSystemTestCase
  setup do
    @user = log_in_as("participant")
    @user.projects.create!(name: "rock")
    HoldPetList.arrived = Queue.new
    HoldPetList.release = Queue.new
  end

  teardown do
    HoldPetList.release << true
    HoldPetList.release = nil
  end

  test "an answer still on its way when the participant logs out in another tab does not sign them back in" do
    visit root_path
    assert_selector ".app.pet", exact_text: "rock"
    # This tab asks for its pets, signed in, and the answer waits.
    page.execute_script("window.pets = fetch('/projects?hold=1', { headers: { Accept: 'application/json' } })")
    Timeout.timeout(Capybara.default_max_wait_time) { HoldPetList.arrived.pop }

    other = open_new_window
    within_window(other) do
      visit root_path(open: "goal")
      click_reloading_the_desktop { within_frame(find(".ship-frame")) { click_button "log out" } }
      assert_no_selector ".app.pet"
    end

    # The answer arrives after the log out, with the cookie it left with.
    HoldPetList.release << true
    assert page.evaluate_async_script("window.pets.then(response => arguments[0](response.ok), () => arguments[0](false))")

    within_window(other) do
      visit root_path(open: "goal")
      assert_selector "#welcome"
      assert_no_selector ".app.pet"
      within_frame(find(".login-frame")) { assert_text "log in with your Hack Club account" }
      assert_no_selector "#window-goal\\.exe", visible: :all
    end
    other.close
  end
end
