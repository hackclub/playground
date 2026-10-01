require "application_system_test_case"

# A desktop window is as tall as its content, never taller. A window with a
# frame, ship.exe or a pet's ship window, follows the page in its frame, and
# past what the screen holds the page scrolls inside it. A drag on a window's
# bottom edge stops at its content.
class WindowFitTest < ApplicationSystemTestCase
  setup do
    # The fixes post with the page's CSRF token, which only renders with this on.
    ActionController::Base.allow_forgery_protection = true
  end

  teardown do
    ActionController::Base.allow_forgery_protection = false
    page.current_window.resize_to(1440, 900)
  end

  test "logged out, login.exe is as tall as the login page, with no rule under it" do
    visit root_path(open: "goal")
    assert_fits "#window-login\\.exe"
    within_frame(find(".login-frame")) do
      assert_text "ship your desktop pet"
      assert_equal "0px", page.evaluate_script("getComputedStyle(document.querySelector('.panel')).borderBottomWidth")
    end
    assert_no_taller_by_hand "#window-login\\.exe"
  end

  test "a ship window fits its list, grows when a fix adds steps, and a drag on its bottom edge stops there" do
    user = log_in_as("participant")
    user.update!(hackatime_access_token: "fake")
    OfflineGithub.repo = OfflineGithub::REPO.with(readme: false, commits: 1)
    pet = user.projects.create!(name: "cobble", description: "a cobble that sits on your screen and naps",
                                ship_message_url: "https://hackclub.slack.com/archives/C0C51NCK1DG/p1759012345678901", playable_url: "https://pet.itch.io/rock", hackatime_projects: [ "rock-pet" ],
                                screenshots: [ { "id" => "shot", "key" => "shot.webp", "url" => "https://playground.hackclub-assets.com/shot.webp" } ])
    open_ship_window(pet)
    window = "#window-ship-#{pet.id}"
    assert_selector window
    assert_fits window
    short = height(window)

    within_frame(find("#{window} iframe")) do
      # No line above the ship row, and no rule under the list.
      assert_equal [ "0px", "0px" ], page.evaluate_script(
        "[getComputedStyle(document.querySelector('#ship-checks > .row')).borderTopWidth, getComputedStyle(document.querySelector('.panel')).borderBottomWidth]")
      fill_in "project[code_url]", with: "https://github.com/pet/rock"
      find("#ship-check-code_url input").send_keys(:enter)
      assert_selector "#ship-check-readme"
      assert_selector "#ship-check-commits"
    end
    assert_fits window
    assert_operator height(window), :>, short, "the window grew with its list"
    assert_no_taller_by_hand window
  end

  test "a long list stops at the screen and scrolls, with the ship row in sight" do
    page.current_window.resize_to(1024, 600)
    user = log_in_as("participant")
    user.update!(hackatime_access_token: "fake")
    pet = user.projects.create!(name: "rock", description: "a small rock")
    open_ship_window(pet)
    window = "#window-ship-#{pet.id}"
    assert_selector window
    within_frame(find("#{window} iframe")) { assert_selector "#ship-checks .shots-grid" }
    screen = page.evaluate_script("document.documentElement.clientHeight")
    assert_operator page.evaluate_script("document.querySelector('#{window}').getBoundingClientRect().bottom"), :<=, screen
    within_frame(find("#{window} iframe")) do
      assert page.evaluate_script("document.documentElement.scrollHeight > innerHeight"), "the list scrolls"
      assert page.evaluate_script("document.querySelector('#ship-checks > .row').getBoundingClientRect().bottom <= innerHeight")
    end
  end

  test "a pet's window is as tall as its page, and follows it to the longer edit page, up to the screen" do
    user = log_in_as("participant")
    pet = user.projects.create!(name: "rock", description: "a small rock")
    open_pet(pet)
    window = "#window-pet-#{pet.id}"
    assert_fits window
    short = height(window)

    within_frame(find("#{window} iframe")) { click_link "edit" }
    within_frame(find("#{window} iframe")) { assert_selector "h2", text: "edit rock" }
    # The window grows a moment after the page changes.
    assert_selector(window) { height(window) > short }
    within_frame(find("#{window} iframe")) do
      assert page.evaluate_script("document.documentElement.scrollHeight > innerHeight"), "the edit page scrolls"
    end
    screen = page.evaluate_script("document.documentElement.clientHeight")
    assert_operator page.evaluate_script("document.querySelector('#{window}').getBoundingClientRect().bottom"), :<=, screen
  end

  # welcome.txt is the one window without a frame, and its text runs past a
  # laptop's screen, so this screen is tall enough for all of it.
  test "a window without a frame stops at its content when its bottom edge is dragged" do
    resize_viewport_to(1440, 2600) do
      forget_open_windows
      visit root_path
      page.execute_script("document.getElementById('welcome').style.top = document.documentElement.style.getPropertyValue('--desktop-top') || '40px'")
      content = page.evaluate_script("(w => w.offsetHeight - w.querySelector('.windowcontent').clientHeight + w.querySelector('.windowcontent').scrollHeight)(document.getElementById('welcome'))")
      foot = page.evaluate_script("document.getElementById('bar').getBoundingClientRect().top")
      assert_operator page.evaluate_script("document.getElementById('welcome').getBoundingClientRect().top") + content, :<, foot - 200, "the screen has room past the text"
      # Dragged down past its text, it stops at the text's end.
      x, y = page.evaluate_script("(b => [b.left + b.width / 2, b.bottom - 2].map(Math.round))(document.getElementById('welcome').getBoundingClientRect())")
      page.driver.browser.action.move_to_location(x, y).click_and_hold.move_to_location(x, foot - 1).release.perform
      assert_equal content, height("#welcome")
      assert_no_taller_by_hand "#welcome"
    end
  end

  private

  # The pet's page opens in its own window, from ship.exe's list.
  def open_pet(pet)
    visit root_path(open: "goal")
    within_frame(find(".ship-frame")) { find_link(pet.name, exact_text: true).send_keys(:enter) }
    within_frame(find("#window-pet-#{pet.id} iframe")) { assert_selector "h2", text: pet.name }
  end

  def open_ship_window(pet)
    open_pet(pet)
    within_frame(find("#window-pet-#{pet.id} iframe")) { find_link("ship").send_keys(:enter) }
  end

  def height(selector) = page.evaluate_script("Math.round(document.querySelector(arguments[0]).getBoundingClientRect().height)", selector)

  # The window's frame is as tall as the page in it. The frame follows the
  # page a moment after the page changes.
  def assert_fits(window)
    fit = lambda do
      page.evaluate_script(<<~JS, window)
        (window => {
          const frame = document.querySelector(window + " iframe")
          const body = frame && frame.contentDocument && frame.contentDocument.body
          return !!body && Math.abs(frame.getBoundingClientRect().height - body.getBoundingClientRect().height) <= 1
        })(arguments[0])
      JS
    end
    page.document.synchronize { raise Capybara::ExpectationNotMet, "#{window} does not fit its page" unless fit.call }
    assert fit.call
  end

  # A drag on the bottom edge, down to the screen's foot, leaves the height as
  # it was. The window starts at the top, so there is room to drag.
  def assert_no_taller_by_hand(window)
    page.execute_script("document.querySelector(arguments[0]).style.top = document.documentElement.style.getPropertyValue('--desktop-top') || '40px'", window)
    before = height(window)
    x, y = page.evaluate_script("(b => [b.left + b.width / 2, b.bottom - 2].map(Math.round))(document.querySelector(arguments[0]).getBoundingClientRect())", window)
    foot = page.evaluate_script("document.documentElement.clientHeight - 1")
    page.driver.browser.action.move_to_location(x, y).click_and_hold.move_to_location(x, [ y + 200, foot ].min).release.perform
    assert_equal before, height(window), "#{window} stays as tall as its content"
  end
end
