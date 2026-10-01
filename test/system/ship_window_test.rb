require "application_system_test_case"

# On the desktop, the pet page sits in the pet's own window, and its ship
# button opens the pet's ship window: a desktop window with the ship list in
# a frame, which drags by its header like the others. Closing it after a fix,
# or shipping from it, reloads the pet page, which shows the ship's notice.
class ShipWindowTest < ApplicationSystemTestCase
  READY = { description: "a pebble that rolls across your screen", code_url: "https://github.com/pet/rock",
            ship_message_url: "https://hackclub.slack.com/archives/C0C51NCK1DG/p1759012345678901", playable_url: "https://pet.itch.io/rock", hackatime_projects: [ "rock-pet" ],
            screenshots: [ { "id" => "shot", "key" => "shot.webp", "url" => "https://playground.hackclub-assets.com/shot.webp" } ] }.freeze

  setup do
    # The fixes post with the page's CSRF token, which only renders with this on.
    ActionController::Base.allow_forgery_protection = true
    @user = log_in_as("participant")
    @user.update!(hackatime_access_token: "fake")
    @project = @user.projects.create!(name: "rock")
  end

  teardown do
    ActionController::Base.allow_forgery_protection = false
    page.current_window.resize_to(1440, 900)
  end

  test "the ship button opens the pet's own window, which drags, and closing it after a fix reloads the pet page" do
    open_pet(@project)
    within_frame(find(pet_frame(@project))) do
      click_link "ship"
      assert_no_selector "dialog[open]"
    end

    window = "#window-ship-#{@project.id}"
    assert_selector "#{window} .headertext", exact_text: "rock.ship"
    assert_settled window
    assert_selector "#window-goal\\.exe .headertext", exact_text: "ship.exe"
    assert_front "window-ship-#{@project.id}"

    # The header drags it, and a press on the X that moves off drags nothing.
    left, top = window_box(window)
    drag [ left + 100, top + 14 ], by: [ 200, 150 ]
    assert_equal [ left + 200, top + 150 ], window_box(window)[0, 2]
    x, y = center("#{window} .windowclose")
    page.driver.browser.action.move_to_location(x, y).click_and_hold.move_to_location(x - 300, y + 200).release.perform
    assert_equal [ left + 200, top + 150 ], window_box(window)[0, 2]
    assert_no_selector "body.dragging"

    # Flung up and to the left, it stays below the credits with its X in
    # sight, and a drag on what shows brings it back.
    drag [ left + 300, top + 164 ], to: [ 0, 0 ]
    assert_equal credits_bottom, window_box(window)[1]
    assert page.evaluate_script("(x => { const b = x.getBoundingClientRect(); return document.elementFromPoint(b.x + 8, b.y + 8) === x })(document.querySelector('#{window} .windowclose'))"),
           "the X takes a press"
    drag [ 20, credits_bottom + 14 ], to: [ 500, 300 ]

    within_frame(find(pet_frame(@project))) { page.execute_script("document.body.dataset.old = ''") }
    within_frame(find("#{window} iframe")) do
      # The list is longer than the window, and the ship button stays in sight below it.
      assert page.evaluate_script("document.documentElement.scrollHeight > innerHeight")
      assert page.evaluate_script("document.querySelector('#ship-checks > .row').getBoundingClientRect().bottom <= innerHeight")
      assert_no_link "← rock"
      fill_in "project[description]", with: "a rock that walks along your taskbar"
    end
    # The X lets go of the field, so what was typed saves before the reload.
    find("#{window} .windowclose").click
    assert_no_selector window
    within_frame(find(pet_frame(@project))) do
      assert_no_selector "body[data-old]"
      assert_text "a rock that walks along your taskbar"
    end
    assert_equal "a rock that walks along your taskbar", @project.reload.description
  end

  test "each pet has one ship window: a second press raises it, and another pet gets its own" do
    pebble = @user.projects.create!(READY.merge(name: "pebble"))
    # A short list keeps rock.ship clear of ship.exe's header.
    @project.update!(READY.except(:description).merge(hackatime_projects: [ "rock-pet-art" ]))
    open_pet(@project)
    within_frame(find(pet_frame(@project))) { click_link "ship" }
    within_frame(find("#window-ship-#{@project.id} iframe")) { fill_in "project[description]", with: "typed, not saved yet" }

    find("#window-pet-#{@project.id} .windowheader").click
    assert_front "window-pet-#{@project.id}"
    within_frame(find(pet_frame(@project))) { find_link("ship").send_keys(:enter) }
    assert_front "window-ship-#{@project.id}"
    assert_selector ".ship-window", count: 1
    within_frame(find("#window-ship-#{@project.id} iframe")) { assert_field "project[description]", with: "typed, not saved yet" }

    # rock.ship lies over the pages now, so the buttons open from the keyboard.
    open_pet(pebble, visit: false)
    within_frame(find(pet_frame(pebble))) { find_link("ship").send_keys(:enter) }
    assert_selector "#window-ship-#{pebble.id} .headertext", exact_text: "pebble.ship"
    assert_selector ".ship-window", count: 2
    assert_front "window-ship-#{pebble.id}"
    # Neither ship window hides the other: the second finds a free spot, or
    # with no room left cascades a step down and right.
    first, second = window_box("#window-ship-#{@project.id}"), window_box("#window-ship-#{pebble.id}")
    assert_not_equal first[0, 2], second[0, 2]
  end

  test "shipping from the window closes it, and the pet page shows the ship and the notice" do
    @project.update!(READY)
    open_pet(@project)
    within_frame(find(pet_frame(@project))) { click_link "ship" }
    window = "#window-ship-#{@project.id}"
    within_frame(find("#{window} iframe")) do
      ship = find("#ship-checks .row button:not([disabled])")
      assert_match(/\Aship \d+h \d+m\z/, ship.text)
      accept_confirm("ship rock? have you read the submission requirements? a reviewer checks your hours next.") { ship.click }
    end

    # The ship asks Hack Club Auth and Hackatime again first.
    assert_no_selector window, wait: 10
    within_frame(find(pet_frame(@project))) do
      assert_selector ".flash.notice", count: 1, exact_text: "shipped! your hours are pending review."
      assert_selector ".badge", text: "pending"
      assert_selector ".ships li", text: "#1"
    end
    assert @project.ships.sole.pending?

    # Opened again, it shows the list, not the page the ship landed on.
    within_frame(find(pet_frame(@project))) { click_link "ship" }
    within_frame(find("#{window} iframe")) { assert_text "your last ship needs its review first" }
  end

  test "in the ship window, a tip shows whole inside the window's frame" do
    open_pet(@project)
    within_frame(find(pet_frame(@project))) { click_link "ship" }
    # Placed and fitted first, so the window stays put under the pointer.
    assert_settled "#window-ship-#{@project.id}"
    within_frame(find("#window-ship-#{@project.id} iframe")) do
      page.execute_script("window.scrollTo(0, document.documentElement.scrollHeight)")
      find("#ship-check-playable_url .tip-mark").hover
      assert_selector "#ship-tip-playable_url", text: "where people get your pet"
      assert page.evaluate_script("(b => b.left >= 0 && b.top >= 0 && b.right <= innerWidth && b.bottom <= innerHeight)(document.querySelector('#ship-tip-playable_url').getBoundingClientRect())")
    end
  end

  test "on a phone, a finger drags the ship window by its header" do
    page.current_window.resize_to(390, 844)
    open_pet(@project)
    within_frame(find(pet_frame(@project))) { click_link "ship" }
    window = "#window-ship-#{@project.id}"
    assert_settled window
    # Headless Chrome keeps a window at least 500px wide, so the screen is measured.
    width, height = page.evaluate_script("[document.documentElement.clientWidth, document.documentElement.clientHeight]")
    left, top, window_width = window_box(window)
    assert_operator left + window_width, :<=, width

    touch [ left + 100, top + 14 ], by: [ 40, 200 ]
    assert_equal [ left + 40, top + 200 ], window_box(window)[0, 2]
    touch [ left + 140, top + 214 ], to: [ width - 1, height - 1 ]
    header = page.evaluate_script("document.querySelector('#{window} .windowheader').getBoundingClientRect().toJSON()")
    assert_operator header["bottom"], :<=, height
    assert_operator width - header["left"], :>=, 80, "80px of the header stays on the screen"
    assert_no_selector "body.dragging"
  end

  private

  # ship.exe's list opens the pet's own window. The desktop's icons for pets
  # have tests of their own. The link opens from the keyboard, as windows may
  # lie over ship.exe.
  def open_pet(project, visit: true)
    if visit
      visit root_path(open: "goal")
      within_frame(find(".ship-frame")) { assert_selector "h2", text: "your pets" }
    end
    within_frame(find(".ship-frame")) { find_link(project.name, exact_text: true).send_keys(:enter) }
    within_frame(find(pet_frame(project))) { assert_selector "h2", text: project.name }
  end

  def pet_frame(project) = "#window-pet-#{project.id} iframe"

  def drag(from, by: nil, to: nil)
    to ||= [ from[0] + by[0], from[1] + by[1] ]
    page.driver.browser.action.move_to_location(*from).click_and_hold.move_to_location(*to).release.perform
  end

  def touch(from, by: nil, to: nil)
    to ||= [ from[0] + by[0], from[1] + by[1] ]
    finger = Selenium::WebDriver::Interactions.pointer(:touch, name: "finger")
    page.driver.browser.action(devices: [ finger ]).move_to_location(*from).pointer_down(:left).move_to_location(*to).pointer_up(:left).perform
  end

  def window_box(selector)
    page.evaluate_script("(box => [box.left, box.top, box.width, box.height].map(Math.round))(document.querySelector(arguments[0]).getBoundingClientRect())", selector)
  end

  def center(selector)
    page.evaluate_script("(box => [box.x + box.width / 2, box.y + box.height / 2].map(Math.round))(document.querySelector(arguments[0]).getBoundingClientRect())", selector)
  end

  def credits_bottom = page.evaluate_script("Math.round(document.getElementById('credits').getBoundingClientRect().bottom)")

  # The window has been placed and fitted to its list: as tall as the page,
  # or as tall as the screen allows.
  def assert_settled(window)
    page.document.synchronize do
      done = page.evaluate_script(<<~JS, window)
        (selector => {
          const win = document.querySelector(selector), frame = win && win.querySelector("iframe")
          const body = frame && frame.contentDocument && frame.contentDocument.querySelector("#ship-checks") && frame.contentDocument.body
          if (!body || !frame.style.getPropertyValue("--page-height") || win.dataset.placing) return false
          // As tall as its page, or shorter because the screen caps it.
          return frame.getBoundingClientRect().height <= body.getBoundingClientRect().height + 1
        })(arguments[0])
      JS
      raise Capybara::ExpectationNotMet, "#{window} is still fitting" unless done
    end
  end

  def front_window
    page.evaluate_script("[...document.querySelectorAll('.window')].filter((w) => w.style.display !== 'none').sort((a, b) => getComputedStyle(b).zIndex - getComputedStyle(a).zIndex)[0].id")
  end

  # The desktop hears the pet page's message a moment after the press.
  def assert_front(id)
    page.document.synchronize { raise Capybara::ExpectationNotMet, "#{front_window} is in front" unless front_window == id }
    assert_equal id, front_window
  end
end
