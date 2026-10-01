require "application_system_test_case"

# The login is login.exe, a window of its own with no icon. A visitor's
# desktop opens it on every load, in front, whatever was saved, and after a
# log out too. A close hides it until the next load, and a drag moves it for
# good, as for any window. A visitor's ship.exe opens it instead of an empty
# ship.exe. A signed-in desktop never shows it.
class LoginWindowTest < ApplicationSystemTestCase
  test "every signed-out load opens login.exe with welcome.txt, in front, clear of the sponsor's icon, with no icon of its own" do
    [ [ 1440, 900 ], [ 1024, 768 ] ].each do |size|
      resize_viewport_to(*size)
      forget_open_windows
      visit root_path
      assert_selector "#welcome"
      assert_selector login_window
      assert_equal %w[welcome window-login.exe], open_windows, "at #{size}"
      assert_no_selector "#window-goal\\.exe", visible: :all
      settled
      %w[#welcome #window-login\\.exe].each { assert_equal 0, overlap(box(it), box(sponsor)), "#{it} covers the sponsor's icon at #{size}" }
      within_frame(login_frame) do
        assert_selector ".login-step.current", text: "Hack Club"
        assert_text "log in with your Hack Club account"
        assert_link "participant"
      end
      assert_no_selector ".app", text: "login.exe"
      assert_selector ".app", exact_text: "ship.exe"
    end
  end

  test "login.exe opens in front of whatever windows the visitor had saved" do
    visit login_path
    page.execute_script("localStorage.setItem('playground-window-state:visitor', arguments[0])",
                        [ { kind: "app", id: "welcome.txt" }, { kind: "guide", page: guide_path, focused: true } ].to_json)
    visit root_path
    within_frame(find(".guide-frame")) { assert_selector "h1", text: "Build a virtual pet in Godot" }
    assert_selector login_window
    assert_equal %w[welcome window-guide.txt window-login.exe], open_windows
  end

  test "on a phone, login.exe is the front window, on every load" do
    resize_viewport_to(390, 844) do
      forget_open_windows
      visit root_path
      assert_selector login_window
      assert_equal "window-login.exe", open_windows.last
      within_frame(login_frame) { assert_link "participant" }
      close_login
      visit root_path
      assert_selector login_window
      assert_equal %w[welcome window-login.exe], open_windows
    end
  end

  test "a visitor's ship.exe opens only login.exe, however it opens" do
    visit root_path
    close_login
    opens_login { icon("ship.exe").click }
    opens_login { icon("ship.exe").send_keys(:enter) }
    opens_login do
      icon("ship.exe").right_click
      click_button "open"
    end
    opens_login { visit root_path(open: "goal") }
    opens_login { visit root_path(open: "ship") }
  end

  test "login.exe drags, comes to the front, fits its page, does not resize, and closes with its X" do
    visit root_path
    assert_selector login_window
    settled
    within_frame(login_frame) { assert_text "development logins" }
    # As tall as its page, and no taller: the frame holds the whole page, and
    # the window adds only its 4px frame, 20px header, and 2px rule.
    fit = page.evaluate_script(<<~JS)
      (win => (frame => [win.offsetHeight - frame.offsetHeight, frame.offsetHeight - Math.ceil(frame.contentDocument.body.getBoundingClientRect().height)])(win.querySelector("iframe")))(document.getElementById("window-login.exe"))
    JS
    assert_equal [ 30, 0 ], fit
    assert_no_selector "#window-login\\.exe .windowresize", visible: :all

    # Clear of welcome.txt's title, which a press raises.
    to = [ 800, 60 ]
    drag_login to: to
    assert_equal to, box(login_window).values_at("left", "top")

    # welcome.txt comes to the front on a press, and login.exe on one in its page.
    find("#welcome .headertext").click
    assert_equal "welcome", open_windows.last
    within_frame(login_frame) { find("h2", text: "ship your desktop pet").click }
    assert_equal "window-login.exe", open_windows.last

    within("#window-login\\.exe .windowheader") { click_button "close", enable_aria_label: true }
    assert_no_selector login_window
    # It opens again where it was left.
    icon("ship.exe").send_keys(:enter)
    assert_equal to, box(login_window).values_at("left", "top")
  end

  test "closed, login.exe comes back with the next load, where it opened, in front" do
    visit root_path
    assert_selector login_window
    settled
    spot = box(login_window).values_at("left", "top")
    close_login
    visit root_path
    assert_selector "#welcome"
    assert_selector login_window
    settled
    assert_equal spot, box(login_window).values_at("left", "top")
    assert_equal %w[welcome window-login.exe], open_windows
  end

  test "dragged, login.exe comes back where it was left, after a close and a reload too" do
    visit root_path
    assert_selector login_window
    settled
    to = [ 420, 120 ]
    drag_login to: to
    visit root_path
    assert_selector login_window
    settled
    assert_equal to, box(login_window).values_at("left", "top")

    close_login
    visit root_path
    assert_selector login_window
    settled
    assert_equal to, box(login_window).values_at("left", "top")
  end

  test "a login leaves login.exe behind, ship.exe opens on the dashboard, and a log out brings login.exe back" do
    visit root_path
    click_reloading_the_desktop { within_frame(login_frame) { click_link "participant" } }
    within_frame(find(".ship-frame")) { assert_text "your meter" }
    assert_no_selector login_window, visible: :all

    click_reloading_the_desktop { within_frame(find(".ship-frame")) { click_button "log out" } }
    assert_selector "#welcome"
    assert_no_selector ".app.pet"
    assert_selector login_window
    assert_equal "window-login.exe", open_windows.last
    within_frame(login_frame) { assert_link "participant" }
  end

  test "an account never shows login.exe, even with it in its saved windows" do
    user = log_in_as("participant")
    # An account's saved windows with login.exe in them, as when its login
    # ended behind the desktop's back.
    visit dashboard_path
    page.execute_script("localStorage.setItem(arguments[0], arguments[1])", "playground-window-state:#{user.id}",
                        [ { kind: "login", id: nil, page: login_path }, { kind: "app", id: "login.exe" } ].to_json)
    visit root_path
    assert_selector ".app", exact_text: "ship.exe"
    assert_no_selector login_window, visible: :all
    icon("ship.exe").send_keys(:enter)
    within_frame(find(".ship-frame")) { assert_text "your meter" }
    assert_no_selector login_window, visible: :all
  end

  private

  def login_window = "#window-login\\.exe"
  def login_frame = find(".login-frame")
  def icon(label) = find(".app", exact_text: label)
  def sponsor = ".app[data-key='armand.sponsor']"

  def box(selector) = page.evaluate_script("(b => ({ left: Math.round(b.left), top: Math.round(b.top), right: Math.round(b.right), bottom: Math.round(b.bottom) }))(document.querySelector(arguments[0]).getBoundingClientRect())", selector)
  def overlap(a, b) = [ [ a["right"], b["right"] ].min - [ a["left"], b["left"] ].max, 0 ].max * [ [ a["bottom"], b["bottom"] ].min - [ a["top"], b["top"] ].max, 0 ].max

  # The open windows' ids, from the back to the front.
  def open_windows
    page.evaluate_script(<<~JS)
      [...document.querySelectorAll(".window")].filter(w => getComputedStyle(w).display !== "none")
        .sort((a, b) => getComputedStyle(a).zIndex - getComputedStyle(b).zIndex).map(w => w.id)
    JS
  end

  # Once every window that opened has been placed.
  def settled
    page.document.synchronize do
      raise Capybara::ExpectationNotMet, "a window is still being placed" if page.evaluate_script("!!document.querySelector('.window[data-placing]')")
    end
  end

  # Drags login.exe by its header so its top left corner lands at the spot.
  def drag_login(to:)
    header = box("#window-login\\.exe .windowheader")
    from = box(login_window)
    page.driver.browser.action.move_to_location(header["left"] + 60, header["top"] + 10).click_and_hold
        .move_to_location(header["left"] + 60 + to[0] - from["left"], header["top"] + 10 + to[1] - from["top"]).release.perform
  end

  def close_login
    assert_selector login_window
    within("#window-login\\.exe .windowheader") { click_button "close", enable_aria_label: true }
    assert_no_selector login_window
  end

  # What the block does opens login.exe in front, on the login, and never ship.exe.
  def opens_login
    yield
    assert_selector login_window
    assert_equal "window-login.exe", open_windows.last
    within_frame(login_frame) { assert_text "log in with your Hack Club account" }
    assert_no_selector "#window-goal\\.exe", visible: :all
    close_login
  end
end
