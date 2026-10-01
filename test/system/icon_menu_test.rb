require "application_system_test_case"

# Every desktop icon has the site's own menu, not the browser's: at the
# pointer on a right click or a long press, and by the icon from the menu key
# or Shift+F10. "open" does what a click does, "rename" edits a pet's label
# in place and saves it, and "move to trash" does what a drag into the trash
# does, only where that drag works. The trash can keeps its own menu.
class IconMenuTest < ApplicationSystemTestCase
  DELETE_MESSAGES = [ "delete rock?", "are you sure you want to delete rock?", "really? rock will be gone forever." ].freeze

  # Each test starts with the account's trash empty and the banana peel on
  # the desktop, and the first visit's desktop, with only welcome.txt open.
  setup do
    @user = log_in_as("participant")
    @user.update!(desktop_trash: [], banana_peel_out: true)
    @rock = @user.projects.create!(name: "rock", description: "naps on your windows")
    forget_open_windows
  end

  test "a right click on a pet opens the menu at the pointer, for that pet alone, and open opens its window" do
    # The pet in a cell with room for the whole menu beside it.
    visit root_path
    page.execute_script("localStorage.setItem('playground-desktop-icons', JSON.stringify({ [arguments[0]]: [4, 3] }))", "pet-#{@rock.id}")
    visit root_path
    close_welcome
    # Two icons selected, then a right click on one of them.
    icon("guide.txt").click
    icon("rock").click(:shift)
    assert_equal [ "guide.txt", "pet-#{@rock.id}" ], selected_keys
    x, y = center_of(icon("rock"))
    page.driver.browser.action.move_to_location(x, y).context_click.perform
    assert_selector "#icon-menu"
    assert_equal [ "open", "rename", "move to trash" ], menu_items
    assert_equal [ x, y ], menu_corner, "the menu opens at the pointer"
    assert_equal [ "pet-#{@rock.id}" ], selected_keys, "the menu is for the icon under the pointer"
    assert_equal "open", focused_text

    within("#icon-menu") { click_button "open" }
    assert_no_selector "#icon-menu"
    assert_selector "#window-pet-#{@rock.id} .headertext", exact_text: "rock"
    assert_equal "pet-#{@rock.id}", focused_key
  end

  test "each kind of icon has its items, move to trash only where a drag into the trash works, and the can keeps its own menu" do
    visit root_path
    close_welcome
    both = [ "open", "move to trash" ]
    {
      "welcome.txt" => both, "guide.txt" => both, "ship.exe" => both, "Hack Club" => both, "Terms & Privacy" => both,
      "Fulfillment" => both, "Security" => both, "banana peel" => both, "armand.sponsor" => [ "open" ],
      "rock" => [ "open", "rename", "move to trash" ]
    }.each do |label, items|
      icon(label).right_click
      assert_equal items, menu_items, label
      send_keys :escape
      assert_no_selector "#icon-menu"
    end

    find(".app[data-key=trash]").right_click
    assert_selector "#trash-menu", text: "the trash is empty"
    assert_no_selector "#icon-menu"
  end

  test "move to trash puts an icon in the trash as a drag does, its window too, and the focus goes to the can" do
    visit root_path
    close_welcome
    icon("guide.txt").click
    assert_selector "#window-guide\\.txt"
    icon("guide.txt").right_click
    within("#icon-menu") { click_button "move to trash" }
    assert_no_selector ".app", exact_text: "guide.txt"
    assert_no_selector "#window-guide\\.txt"
    assert_includes find(".app[data-key=trash] .appicon")[:src], "/landing/trash-full-"
    assert_equal "trash", focused_key
    assert_account_trash [ "guide.txt" ]

    # A link off the site and the banana peel go the same way.
    [ "Hack Club", "banana peel" ].each do |label|
      icon(label).right_click
      within("#icon-menu") { click_button "move to trash" }
      assert_no_selector ".app", exact_text: label
    end
    assert_account_trash [ "guide.txt", "Hack Club", "banana peel" ]
    find(".app[data-key=trash]").click
    within("#trash-menu") { assert_equal [ "restore guide.txt", "restore Hack Club", "restore banana peel", "restore all" ], all("[role=menuitem]").map(&:text) }
  end

  test "move to trash on a pet asks with its delete popups, and on a shipped pet says it cannot be deleted" do
    goose = @user.projects.create!(name: "goose")
    goose.ships.create!(user: @user)
    visit root_path
    close_welcome

    icon("rock").right_click
    within("#icon-menu") { click_button "move to trash" }
    assert_no_selector ".app", exact_text: "rock"
    within_frame(find(".delete-frame")) do
      assert_equal DELETE_MESSAGES, all("dialog.popup[open] p").map(&:text)
      within(all("dialog.popup[open]")[1]) { click_button "no" }
    end
    assert_no_selector ".delete-frame", visible: true
    assert_selector ".app", exact_text: "rock"
    assert_equal "pet-#{@rock.id}", focused_key, "the focus comes back to the pet"

    icon("goose").right_click
    within("#icon-menu") { click_button "move to trash" }
    within_frame(find(".delete-frame")) do
      assert_selector "dialog.popup[open]", count: 1
      assert_selector "dialog.popup[open] p", exact_text: "a shipped pet cannot be deleted"
      click_button "ok"
    end
    assert_no_selector ".delete-frame", visible: true
    assert_selector ".app", exact_text: "goose"
    assert Project.exists?(goose.id)

    icon("rock").right_click
    within("#icon-menu") { click_button "move to trash" }
    within_frame(find(".delete-frame")) do
      within(all("dialog.popup[open]")[2]) { click_button "delete it" }
      within(all("dialog.popup[open]")[0]) { click_button "delete" }
      within(all("dialog.popup[open]")[0]) { click_button "yes" }
    end
    assert_no_selector ".delete-frame", visible: true
    assert_no_selector ".app", exact_text: "rock"
    assert_not Project.exists?(@rock.id)
    assert_equal "trash", focused_key
    assert_account_trash [], "a pet never waits in the trash"
  end

  test "rename edits the label in place and saves the name, and the pet's windows, ship.exe's list, and its spot follow" do
    visit root_path
    page.execute_script("localStorage.setItem('playground-desktop-icons', JSON.stringify({ [arguments[0]]: [6, 2] }))", "pet-#{@rock.id}")
    visit root_path(open: "goal")
    assert_equal "6,2", icon("rock")["data-cell"]
    within_frame(find(".ship-frame")) { assert_link "rock" }
    # The pet's window, its ship window, and ship.exe lie off to the right, clear of the icons.
    icon("rock").send_keys(:enter)
    within_frame(find("#window-pet-#{@rock.id} iframe")) { click_link "ship" }
    assert_selector "#window-ship-#{@rock.id} .headertext", exact_text: "rock.ship"
    page.execute_script(<<~JS)
      document.querySelectorAll(".pet-window, .ship-window, [id='window-goal.exe'], #welcome").forEach(win => Object.assign(win.style, { left: "900px", top: "40px" }))
    JS

    icon("rock").right_click
    within("#icon-menu") { click_button "rename" }
    assert_selector ".app.pet .rename"
    assert_no_selector ".app.pet p", visible: true
    assert_equal [ "rock", 0, 4, true ], page.evaluate_script("(f => [f.value, f.selectionStart, f.selectionEnd, f === document.activeElement])(document.querySelector('.rename'))"),
                 "the field holds the name, all of it selected"
    find(".rename").send_keys("pebble", :enter)
    assert_no_selector ".rename"
    assert_selector ".app.pet", exact_text: "pebble"
    assert_equal "pet-#{@rock.id}", focused_key
    assert_saved_name "pebble"

    assert_selector "#window-pet-#{@rock.id} .headertext", exact_text: "pebble"
    within_frame(find("#window-pet-#{@rock.id} iframe")) { assert_selector "h2", text: "pebble" }
    assert_selector "#window-ship-#{@rock.id} .headertext", exact_text: "pebble.ship"
    within_frame(find(".ship-frame")) do
      assert_link "pebble"
      assert_no_link "rock"
    end
    visit root_path
    assert_equal "6,2", icon("pebble")["data-cell"], "the icon keeps its saved spot"
  end

  test "a name the edit page refuses shows why beside the label and the old name comes back, Escape keeps the name, and a press elsewhere saves" do
    visit root_path
    close_welcome
    start_rename "rock"
    find(".rename").send_keys(:backspace, :enter)
    assert_selector "#rename-error[role=alert]", exact_text: "Name can't be blank"
    assert_selector ".app.pet", exact_text: "rock"
    assert_equal "rock", @rock.reload.name
    beside = page.evaluate_script(<<~JS)
      (([error, label]) => (error.left >= label.right || error.right <= label.left) && error.top < label.bottom && label.top < error.bottom)
        ([document.getElementById("rename-error"), document.querySelector(".app.pet p")].map(el => el.getBoundingClientRect()))
    JS
    assert beside, "the error lies beside the label"
    click_wallpaper
    assert_no_selector "#rename-error"

    start_rename "rock"
    find(".rename").send_keys("boulder", :escape)
    assert_no_selector ".rename"
    assert_selector ".app.pet", exact_text: "rock"
    assert_equal "pet-#{@rock.id}", focused_key

    start_rename "rock"
    find(".rename").send_keys("pebble")
    click_wallpaper
    assert_no_selector ".rename"
    assert_selector ".app.pet", exact_text: "pebble"
    assert_saved_name "pebble"
  end

  test "from the keyboard, Shift+F10 or the menu key opens the menu by the icon, the arrows and Enter choose, and the focus comes back" do
    visit root_path
    close_welcome
    page.execute_script("document.querySelector(arguments[0]).focus()", ".app[data-key='pet-#{@rock.id}']")
    active.send_keys([ :shift, :f10 ])
    assert_selector "#icon-menu"
    assert_equal "open", focused_text
    assert_menu_by_icon "pet-#{@rock.id}"
    [ [ :down, "rename" ], [ :down, "move to trash" ], [ :down, "open" ], [ :up, "move to trash" ] ].each do |key, text|
      active.send_keys(key)
      assert_equal text, focused_text
    end
    active.send_keys(:escape)
    assert_no_selector "#icon-menu"
    assert_equal "pet-#{@rock.id}", focused_key

    press_menu_key
    assert_selector "#icon-menu"
    assert_menu_by_icon "pet-#{@rock.id}"
    active.send_keys(:down, :enter)
    assert_selector ".rename"
    active.send_keys("pebble", :enter)
    assert_selector ".app.pet", exact_text: "pebble"
    assert_equal "pet-#{@rock.id}", focused_key
    assert_saved_name "pebble"

    active.send_keys([ :shift, :f10 ])
    active.send_keys(:enter)
    assert_selector "#window-pet-#{@rock.id} .headertext", exact_text: "pebble"
    assert_equal "pet-#{@rock.id}", focused_key

    # The can's own menu opens from the keys too.
    page.execute_script("document.querySelector('.app[data-key=trash]').focus()")
    active.send_keys([ :shift, :f10 ])
    assert_selector "#trash-menu", text: "the trash is empty"
  end

  test "a long press opens the menu where the finger is and opens nothing, on a desktop and a phone, and a drag or a tap does as before" do
    [ [ 1440, 900 ], [ 390, 844 ] ].each do |size|
      resize_viewport_to(*size) do
        forget_open_windows
        visit root_path
        close_welcome
        at = "at #{size.join("x")}"
        x, y = center_of(icon("rock").find(".appicon"))
        touch { it.move_to_location(x, y).pointer_down(:left).pause(device: finger, duration: 0.8).pointer_up(:left) }
        assert_selector "#icon-menu", wait: 2
        assert_equal [ "open", "rename", "move to trash" ], menu_items, at
        assert_menu_at x, y, at
        assert_no_selector "#window-pet-#{@rock.id}"

        # A tap on an item chooses it.
        ix, iy = center_of(find("#icon-menu button", text: "open"))
        touch { it.move_to_location(ix, iy).pointer_down(:left).pointer_up(:left) }
        assert_no_selector "#icon-menu"
        assert_selector "#window-pet-#{@rock.id}", visible: true
        within("#window-pet-#{@rock.id} .windowheader") { click_button "close", enable_aria_label: true }

        # A finger that moves drags the icon, here to the bottom row's right half, and opens no menu.
        from = icon("rock")["data-cell"]
        touch { it.move_to_location(x, y).pointer_down(:left).move_to_location(size[0] * 3 / 4, size[1] - 100).pause(device: finger, duration: 0.8).pointer_up(:left) }
        assert_no_selector ".app.moving"
        assert_no_selector "#icon-menu"
        assert_not_equal from, icon("rock")["data-cell"], at
        page.execute_script("localStorage.removeItem('playground-desktop-icons')")
      end
    end
  end

  test "the menu stays inside the screen and above the taskbar, and closes when a window's frame takes a press" do
    visit root_path
    columns, rows = find("#apps", visible: :all)["data-grid"].split.map(&:to_i)
    page.execute_script("localStorage.setItem('playground-desktop-icons', JSON.stringify({ [arguments[0]]: [arguments[1] - 1, arguments[2] - 1] }))",
                        "pet-#{@rock.id}", columns, rows)
    visit root_path
    close_welcome
    box = page.evaluate_script("document.querySelector(arguments[0]).getBoundingClientRect().toJSON()", ".app[data-key='pet-#{@rock.id}']")
    page.driver.browser.action.move_to_location((box["right"] - 2).round, (box["bottom"] - 2).round).context_click.perform
    assert_selector "#icon-menu"
    assert_menu_in_view
    send_keys :escape

    # Held on the label there, the menu moves in and up under the finger, and
    # the finger's release chooses nothing. Chrome's own touch input ends a
    # long hold in a click where the finger lifts, as a phone may.
    x, y = center_of(icon("rock").find("p"))
    page.driver.browser.execute_cdp("Input.dispatchTouchEvent", type: "touchStart", touchPoints: [ { x:, y: } ])
    sleep 0.8
    page.driver.browser.execute_cdp("Input.dispatchTouchEvent", type: "touchEnd", touchPoints: [])
    assert_selector "#icon-menu"
    assert_menu_in_view
    assert page.evaluate_script("document.elementFromPoint(arguments[0], arguments[1]).matches('#icon-menu button')", x, y), "an item lies under the finger"
    sleep 0.3
    assert_selector "#icon-menu"
    assert_no_selector ".rename"
    assert_no_selector "#window-pet-#{@rock.id}"
    assert_no_selector ".delete-frame", visible: true
    send_keys :escape

    # A press inside a framed window closes it, as it closes the can's.
    icon("ship.exe").click
    within_frame(find(".ship-frame")) { assert_text "your pets" }
    page.execute_script("Object.assign(document.getElementById('window-goal.exe').style, { left: '500px', top: '120px' })")
    icon("rock").right_click
    assert_selector "#icon-menu"
    x, y = page.evaluate_script("(b => [b.left + b.width / 2, b.top + b.height / 2].map(Math.round))(document.querySelector('.ship-frame').getBoundingClientRect())")
    page.driver.browser.action.move_to_location(x, y).click.perform
    assert_no_selector "#icon-menu"
  end

  private
    def icon(label) = find(".app", exact_text: label)

    def active = page.driver.browser.switch_to.active_element

    def selected_keys = all(".app.selected").map { it["data-key"] }

    def menu_items = all("#icon-menu [role=menuitem]").map(&:text)

    def focused_text = page.evaluate_script("document.activeElement.textContent")

    def focused_key = page.evaluate_script("document.activeElement.dataset.key ?? null")

    def center_of(element)
      box = page.evaluate_script("arguments[0].getBoundingClientRect().toJSON()", element)
      [ (box["x"] + box["width"] / 2).round, (box["y"] + box["height"] / 2).round ]
    end

    def menu_corner = page.evaluate_script("(m => [m.left, m.top].map(Math.round))(document.getElementById('icon-menu').getBoundingClientRect())")

    # The menu's top left corner at (x, y), or as near as the whole menu fits
    # inside the screen and above the taskbar.
    def assert_menu_at(x, y, message = nil)
      spot = page.evaluate_script(<<~JS, x, y)
        ((menu, x, y) => [Math.max(0, Math.min(x, document.documentElement.clientWidth - Math.ceil(menu.width))),
          Math.max(0, Math.min(y, document.getElementById("bar").getBoundingClientRect().top - Math.ceil(menu.height)))].map(Math.round))
          (document.getElementById("icon-menu").getBoundingClientRect(), arguments[0], arguments[1])
      JS
      assert_equal spot, menu_corner, message
      assert_menu_in_view
    end

    # A key's menu has no pointer, so it opens by the icon, 16px in from its
    # left and up from its bottom, as the can's does.
    def assert_menu_by_icon(key)
      box = page.evaluate_script("document.querySelector(arguments[0]).getBoundingClientRect().toJSON()", ".app[data-key='#{key}']")
      assert_menu_at((box["left"] + 16).round, (box["bottom"] - 16).round, "a key's menu opens by the icon")
    end

    def assert_menu_in_view
      inside = page.evaluate_script(<<~JS)
        (menu => menu.left >= 0 && menu.top >= 0 && menu.right <= document.documentElement.clientWidth &&
          menu.bottom <= document.getElementById("bar").getBoundingClientRect().top)(document.getElementById("icon-menu").getBoundingClientRect())
      JS
      assert inside, "the menu lies inside the screen, above the taskbar"
    end

    # welcome.txt opens with a first visit, over the icons on a phone.
    def close_welcome
      find("#welcome .windowclose").send_keys(:enter)
      assert_no_selector "#welcome"
    end

    def start_rename(label)
      icon(label).right_click
      within("#icon-menu") { click_button "rename" }
      assert_selector ".rename"
    end

    # A press on the wallpaper, clear of the icons, the logo's windows, and the rock.
    def click_wallpaper
      page.driver.browser.action.move_to_location(1100, 600).click.perform
    end

    # The menu key, which WebDriver has no name for, as Chrome gets it from a keyboard.
    def press_menu_key
      key = { key: "ContextMenu", code: "ContextMenu", windowsVirtualKeyCode: 93, nativeVirtualKeyCode: 93 }
      page.driver.browser.execute_cdp("Input.dispatchKeyEvent", type: "rawKeyDown", **key)
      page.driver.browser.execute_cdp("Input.dispatchKeyEvent", type: "keyUp", **key)
    end

    def finger = @finger ||= Selenium::WebDriver::Interactions.pointer(:touch, name: "finger")

    def touch
      yield(page.driver.browser.action(devices: [ finger ])).perform
    end

    # The rename saves in the background, so this waits for the saved name.
    def assert_saved_name(name)
      deadline = Time.now + Capybara.default_max_wait_time
      sleep 0.05 until @rock.reload.name == name || Time.now > deadline
      assert_equal name, @rock.name
    end

    def assert_account_trash(icons, message = nil)
      deadline = Time.now + Capybara.default_max_wait_time
      sleep 0.05 until @user.reload.desktop_trash == icons || Time.now > deadline
      assert_equal icons, @user.desktop_trash, message
    end
end
