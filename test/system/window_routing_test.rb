require "application_system_test_case"

# Each desktop window has one job: ship.exe shows the dashboard, a pet's
# window shows that pet's page and its edit page, and a ship window shows its
# checks. A link, a save, or a redirect to another window's page opens that
# window on it, and no window ever shows another's page.
class WindowRoutingTest < ApplicationSystemTestCase
  setup do
    @user = log_in_as("participant")
    @rock = @user.projects.create!(name: "rock", description: "naps on your windows")
  end

  # The phone test sizes the page, so the next test gets the browser's size back.
  teardown { page.driver.browser.execute_cdp("Emulation.clearDeviceMetricsOverride") }

  test "ship.exe's edit button opens the pet's window on its edit page, where the way back and a save stay" do
    edit_rename_and_go_back
  end

  test "on a phone, ship.exe's edit button opens the pet's window on its edit page, where the way back and a save stay" do
    resize_viewport_to(390, 844) { edit_rename_and_go_back }
  end

  test "on a slow line, the edit page shows no copy of itself to type into before it loads" do
    visit root_path(open: "goal")
    within_frame(goal) { click_link "edit", href: edit_project_path(@rock) }
    within_frame(pet_frame) do
      assert_selector "h2", text: "edit rock"
      click_link "← rock"
      assert_no_selector "h2", text: "edit rock"
      # Turbo keeps a copy of each page it leaves. A copy of the edit page
      # shown while the page loads would take typing, then lose it.
      slow_network do
        click_link "edit"
        fill_in "project[name]", with: "boulder"
        assert_no_selector "html[aria-busy]"
        assert_field "project[name]", with: "boulder"
      end
    end
  end

  test "a delete from the edit page closes the pet's window and raises ship.exe with the list" do
    visit root_path(open: "goal")
    within_frame(goal) { click_link "edit", href: edit_project_path(@rock) }
    within_frame(pet_frame) do
      click_button "delete pet"
      within(popup("really? rock will be gone forever.")) { click_button "delete it" }
      within(popup("delete rock?")) { click_button "delete" }
      within(popup("are you sure you want to delete rock?")) { click_button "yes" }
    end
    assert_no_selector pet_window
    assert_no_selector ".app.pet"
    within_frame(goal) { assert_text "no pets yet." }
    assert_equal "window-goal.exe", front_window
    assert_not Project.exists?(@rock.id)
  end

  test "a page loaded in the wrong window by other means goes to its own, and the window goes back to its page" do
    visit root_path(open: "goal")
    within_frame(goal) { assert_text "your pets" }
    page.execute_script("document.querySelector('.ship-frame').src = #{edit_project_path(@rock).to_json}")
    within_frame(pet_frame) { assert_selector "h2", text: "edit rock" }
    within_frame(goal) do
      assert_text "your pets"
      assert_equal dashboard_path, frame_path
    end
  end

  test "signed out behind its back, a pet's window sends the login to login.exe with its alert and closes instead of going round" do
    visit root_path
    # The pet's icon may lie under ship.exe, which the login opened, so Enter opens it.
    icon("rock").send_keys(:enter)
    within_frame(pet_frame) { assert_selector "h2", text: "rock" }
    # The session stops signing anyone in. Deleting the cookie would not do:
    # every response sets it again, so one still on its way signs back in.
    @user.destroy!
    within_frame(pet_frame) { click_link "edit" }
    # The login goes to login.exe, and the window goes after its own page
    # sends it there again. Each is a round trip or two, which the full
    # suite's load can stretch past the default wait.
    using_wait_time(10) do
      within_frame(login_frame) do
        assert_text "log in with your Hack Club account"
        assert_selector ".flash.alert", count: 1, exact_text: "log in first"
      end
      assert_no_selector pet_window, visible: :all
    end
    # ship.exe's dashboard, loaded signed out, goes to the login too, and
    # ship.exe goes rather than stay empty.
    page.execute_script("document.querySelector('.ship-frame').contentWindow.location.reload()")
    using_wait_time(10) { assert_no_selector "#window-goal\\.exe", visible: :all }
    within_frame(login_frame) { assert_text "log in with your Hack Club account" }
  end

  test "logging out from ship.exe reloads the desktop signed out, with the pets' windows gone" do
    visit root_path(open: "goal")
    within_frame(goal) { click_link "rock" }
    within_frame(pet_frame) { assert_selector "h2", text: "rock" }
    # The pet's window may open over ship.exe, so it moves to the side ship.exe leaves.
    page.execute_script(<<~JS)
      (() => {
        const goal = document.getElementById("window-goal.exe").getBoundingClientRect()
        const pet = document.querySelector(".pet-window")
        const left = goal.left > pet.offsetWidth + 20 ? 10 : goal.right + 10
        Object.assign(pet.style, { left: left + "px", top: "40px" })
      })()
    JS
    click_reloading_the_desktop { within_frame(goal) { click_button "log out" } }
    assert_no_selector ".app.pet"
    assert_no_selector ".pet-window"
    assert_current_path root_path
    # The visitor's desktop opens as a first visit's, with welcome.txt clear of the icons.
    assert_operator page.evaluate_script("document.getElementById('welcome').getBoundingClientRect().left"), :>, 300
    icon("ship.exe").click
    within_frame(login_frame) { assert_text "log in with your Hack Club account" }
    assert_no_selector "#window-goal\\.exe", visible: :all
  end

  private

  # Each request of the browser's waits 1.5 seconds before it goes.
  def slow_network
    page.driver.browser.execute_cdp("Network.enable")
    page.driver.browser.execute_cdp("Network.emulateNetworkConditions", offline: false, latency: 1500, downloadThroughput: -1, uploadThroughput: -1)
    yield
  ensure
    page.driver.browser.execute_cdp("Network.emulateNetworkConditions", offline: false, latency: 0, downloadThroughput: -1, uploadThroughput: -1)
  end

  def goal = find(".ship-frame")
  def login_frame = find(".login-frame")
  def pet_window = "#window-pet-#{@rock.id}"
  def pet_frame = find("#{pet_window} iframe")
  def icon(name) = find(".app", exact_text: name)
  def frame_path = page.evaluate_script("location.pathname")
  def popup(message) = find("dialog.popup[open]") { it.has_css?("p", exact_text: message, wait: false) }

  def front_window
    page.evaluate_script(<<~JS)
      [...document.querySelectorAll(".window")].filter(win => win.style.display !== "none")
        .sort((a, b) => Number(getComputedStyle(b).zIndex) - Number(getComputedStyle(a).zIndex))[0].id
    JS
  end

  # From ship.exe's list to the edit page in the pet's window, back to the pet
  # page there, and a rename saved there. ship.exe keeps its list throughout.
  def edit_rename_and_go_back
    visit root_path(open: "goal")
    within_frame(goal) { click_link "edit", href: edit_project_path(@rock) }
    assert_selector "#{pet_window} .headertext", exact_text: "rock"
    within_frame(pet_frame) { assert_selector "h2", text: "edit rock" }
    within_frame(goal) do
      assert_text "your pets"
      assert_equal dashboard_path, frame_path
    end

    within_frame(pet_frame) do
      click_link "← rock"
      assert_no_selector "h2", text: "edit rock"
      assert_selector "h2", text: "rock"
      click_link "edit"
      fill_in "project[name]", with: "boulder"
      click_button "save"
      assert_selector "h2", text: "boulder"
      assert_equal project_path(@rock), frame_path
    end
    assert_selector ".pet-window", count: 1
    assert_selector "#{pet_window} .headertext", exact_text: "boulder"
    # ship.exe's list takes the new name.
    within_frame(goal) do
      assert_link "boulder"
      assert_equal dashboard_path, frame_path
    end
  end
end
