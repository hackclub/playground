require "application_system_test_case"

# The pet page's ship button opens ship.exe, which lists only what blocks
# shipping, each with its own fix. A fix saves when it changes, with no save
# button, and its step turns to a tick. Once nothing blocks, the popup ships.
# On its own page the popup drags by its title bar. On the desktop it is a
# window instead (see the ship window test).
class ShipPopupTest < ApplicationSystemTestCase
  class LocalStore < MemoryScreenshotStore
    def url(key) = "#{Capybara.current_session.server.base_url}/icon.png?#{key}"
  end

  setup do
    ScreenshotStore.current = LocalStore.new
    # The fixes post with the page's CSRF token, which only renders with this on.
    ActionController::Base.allow_forgery_protection = true
    @user = log_in_as("participant")
    @user.update!(hackatime_access_token: "fake")
    @project = @user.projects.create!(name: "rock")
    @shot = Tempfile.new([ "shot", ".png" ]).tap { it.binmode; it.write(image_bytes(1280, 720)); it.close }
  end

  teardown do
    ActionController::Base.allow_forgery_protection = false
    page.current_window.resize_to(1440, 900)
    @shot.unlink
    @shots&.each(&:unlink)
  end

  test "every blocker is fixed inside the popup, and then the pet ships" do
    visit project_path(@project)
    assert_no_text "the description needs at least 20 characters"
    click_link "ship"
    assert_selector "dialog.ship-popup[open] .popup-title", text: "ship.exe"
    assert_equal 480, popup_box["width"]
    assert_equal "none", page.evaluate_script("getComputedStyle(document.querySelector('dialog.ship-popup')).resize")
    assert_button "ship", disabled: true

    within "dialog.ship-popup" do
      # A partial fix stays on the list, still to do.
      commit field("project[description]"), "a small rock"
      assert_selector "#ship-check-description.todo .icon", text: "!"
      commit field("project[description]"), "a small rock that naps on your taskbar"
      assert_selector "#ship-check-description.ok"

      find("input[type=checkbox][value='rock-pet']").check
      assert_selector "#ship-check-hackatime_projects.ok"
      # New hours waited for a Hackatime project, and the project has some.
      assert_no_selector "#ship-check-new_hours"

      commit field("project[code_url]"), "not a url"
      assert_selector "#ship-check-code_url .banner.alert", text: "Code url must be a full http(s) link"
      assert_field "project[code_url]", with: "not a url"
      commit field("project[code_url]"), "https://github.com/pet/rock"
      assert_selector "#ship-check-code_url.ok"
      assert_no_selector "#ship-check-code_url .banner"

      commit field("project[playable_url]"), "https://pet.itch.io/rock"
      assert_selector "#ship-check-playable_url.ok"

      # Three at once: the list checks the pet again after the first, and the
      # others still land in it.
      find("input[type=file]", visible: :hidden).set(shots.map(&:path))
      assert_selector "#ship-check-screenshot.ok"
      assert_selector ".thumb:not(.pending)", count: 3
      assert_no_selector ".thumb.pending"

      commit field("project[ship_message_url]"), "https://hackclub.slack.com/archives/C0C51NCK1DG/p1759012345678901"
      assert_selector "#ship-check-ship_message_url.ok"

      assert_text "all set! everything checks out."
      ship = find("#ship-checks .row button:not([disabled])")
      assert_match(/\Aship \d+h \d+m\z/, ship.text)
      accept_confirm("ship rock? have you read the submission requirements? a reviewer checks your hours next.") { ship.click }
    end

    assert_text "shipped! your hours are pending review."
    assert_no_selector "dialog.ship-popup[open]"
    assert_selector ".ships li", text: "#1"
    assert_selector ".carousel img.shot", count: 3, visible: :all
    @project.reload
    assert_equal 3, @project.screenshots.size
    assert_equal @project.screenshot_urls, @project.ships.sole.snapshot["screenshots"]
    assert_equal @project.screenshot_url, @project.ships.sole.snapshot["screenshot_url"]
    assert_equal [ "rock-pet" ], @project.hackatime_projects
    assert_equal "https://github.com/pet/rock", @project.code_url
    assert @project.ships.sole.pending?
  end

  test "by keyboard, Tab stays in the popup, and Escape saves the field being typed in and closes it" do
    @project.update!(hackatime_projects: [ "rock-pet" ], playable_url: "https://pet.itch.io/rock")
    visit project_path(@project)
    find_link("ship").send_keys(:enter)
    assert_selector "dialog.ship-popup[open] textarea"
    assert_equal "close", active("aria-label")

    stops = 16.times.map do
      page.send_keys(:tab)
      assert page.evaluate_script("!!document.activeElement.closest('dialog.ship-popup')"), "focus stays in the popup"
      active("name") || active("aria-label") || active("class")
    end
    # The requirements link comes first, and a step's tip mark takes a stop of its own.
    cycle = [ nil, "project[description]", "more about this", "project[code_url]", "shot-cell add", "more about this",
              "project[ship_message_url]", "close" ]
    assert_equal cycle, stops.first(8)
    assert_equal cycle, stops.last(8), "Tab wraps around"

    2.times { page.send_keys(:tab) }
    page.send_keys("a rock that walks along your taskbar")
    page.send_keys(:escape)

    assert_no_selector "dialog.ship-popup[open]"
    assert_selector "p", text: "a rock that walks along your taskbar"
    assert_equal "a rock that walks along your taskbar", @project.reload.description
  end

  test "on its own page, the popup drags by its title bar, stays in reach, and opens where it did again" do
    visit project_path(@project)
    click_link "ship"
    assert_selector "dialog.ship-popup[open] textarea"
    start = popup_box
    head = [ start["left"] + 100, start["top"] + 14 ]

    page.driver.browser.action.move_to_location(*head).click_and_hold.move_to_location(head[0] - 150, head[1] + 200).release.perform
    assert_equal [ start["left"] - 150, start["top"] + 200 ], popup_box.values_at("left", "top")

    # A press on the X that moves off drags nothing.
    x, y = page.evaluate_script("(b => [b.x + b.width / 2, b.y + b.height / 2].map(Math.round))(document.querySelector('.ship-popup .popup-close').getBoundingClientRect())")
    page.driver.browser.action.move_to_location(x, y).click_and_hold.move_to_location(x - 200, y + 100).release.perform
    assert_equal [ start["left"] - 150, start["top"] + 200 ], popup_box.values_at("left", "top")

    # Flung past each corner, 80px of the title bar and all of its height stay
    # on the screen, and past the left edge the X does too.
    width, height = page.evaluate_script("[document.documentElement.clientWidth, document.documentElement.clientHeight]")
    [ [ 0, 0 ], [ width - 1, 0 ], [ width - 1, height - 1 ], [ 0, height - 1 ] ].each do |to|
      # Held by the part of the title bar that shows, at the end that trails.
      head, close = page.evaluate_script("['.popup-head', '.popup-close'].map((s) => document.querySelector('.ship-popup ' + s).getBoundingClientRect().toJSON())")
      grab = [ (to[0].zero? ? [ close["left"], width ].min - 10 : [ head["left"], 0 ].max + 10).round, (head["top"] + 10).round ]
      page.driver.browser.action.move_to_location(*grab).click_and_hold.move_to_location(*to).release.perform
      title = page.evaluate_script("document.querySelector('.ship-popup .popup-head').getBoundingClientRect().toJSON()")
      assert_operator title["top"], :>=, 0, "flung to #{to}"
      assert_operator title["bottom"], :<=, height, "flung to #{to}"
      assert_operator [ title["right"], width ].min - [ title["left"], 0 ].max, :>=, 80, "flung to #{to}"
      assert_operator page.evaluate_script("document.querySelector('.ship-popup .popup-close').getBoundingClientRect().left"), :>=, 0 if to[0].zero?
    end

    # Focus stays inside, and a closed popup opens where it always does.
    page.send_keys(:tab)
    assert page.evaluate_script("!!document.activeElement.closest('dialog.ship-popup')")
    page.send_keys(:escape)
    assert_no_selector "dialog.ship-popup[open]"
    click_link "ship"
    assert_selector "dialog.ship-popup[open] textarea"
    assert_equal start.values_at("left", "top"), popup_box.values_at("left", "top")
  end

  test "a tip shows on hover, keyboard focus, and a tap, and hides on moving away, Escape, or a tap elsewhere" do
    visit project_path(@project)
    click_link "ship"
    mark = "#ship-check-code_url .tip-mark"
    tip = "#ship-tip-code_url"
    assert_selector mark

    find(mark).hover
    assert_selector tip, text: "a public link where anyone can read your pet's code"
    assert page.evaluate_script("(b => b.left >= 0 && b.top >= 0 && b.right <= innerWidth && b.bottom <= innerHeight)(document.querySelector('#{tip}').getBoundingClientRect())")
    find("#ship-check-description textarea").hover
    assert_no_selector tip

    page.execute_script("document.querySelector('#{mark}').focus()")
    assert_selector tip
    page.send_keys(:escape)
    assert_no_selector tip
    # The first Escape only hides the tip.
    assert_selector "dialog.ship-popup[open]"
    page.send_keys(:tab)
    assert_no_selector tip

    finger = Selenium::WebDriver::Interactions.pointer(:touch, name: "finger")
    x, y = page.evaluate_script("(b => [b.x + b.width / 2, b.y + b.height / 2].map(Math.round))(document.querySelector('#{mark}').getBoundingClientRect())")
    page.driver.browser.action(devices: [ finger ]).move_to_location(x, y).pointer_down(:left).pointer_up(:left).perform
    assert_selector tip
    head = page.evaluate_script("(b => [b.x + 20, b.y + b.height / 2].map(Math.round))(document.querySelector('#ship-check-description').getBoundingClientRect())")
    page.driver.browser.action(devices: [ finger ]).move_to_location(*head).pointer_down(:left).pointer_up(:left).perform
    assert_no_selector tip
  end

  test "on a phone, a finger drags the popup by its title bar" do
    page.current_window.resize_to(390, 844)
    visit project_path(@project)
    click_link "ship"
    assert_selector "dialog.ship-popup[open] textarea"
    start = popup_box
    finger = Selenium::WebDriver::Interactions.pointer(:touch, name: "finger")
    page.driver.browser.action(devices: [ finger ]).move_to_location(start["left"] + 60, start["top"] + 14)
      .pointer_down(:left).move_to_location(start["left"] + 90, start["top"] + 314).pointer_up(:left).perform
    assert_equal [ start["left"] + 30, start["top"] + 300 ], popup_box.values_at("left", "top")
    assert page.evaluate_script("document.documentElement.scrollWidth <= document.documentElement.clientWidth")
  end

  private

  def shots
    @shots ||= [ [ 1280, 720 ], [ 1600, 900 ], [ 900, 1200 ] ].each_with_index.map do |(width, height), n|
      Tempfile.new([ "shot-#{n}", ".png" ]).tap { it.binmode; it.write(image_bytes(width, height)); it.close }
    end
  end

  def field(name) = find_field(name)

  # A fix saves on change, which a field fires when it loses focus.
  def commit(field, value)
    field.set(value)
    field.send_keys(:tab)
  end

  def popup_box = page.evaluate_script("document.querySelector('dialog.ship-popup').getBoundingClientRect().toJSON()")

  def active(attribute) = page.evaluate_script("document.activeElement.getAttribute('#{attribute}')")
end
