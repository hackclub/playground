require "application_system_test_case"

# A participant's pets on the desktop: each is an icon that opens its pet page
# in a window of its own. ship.exe holds the meter and the pet list. A trash can
# takes icons off the desktop and puts them back, and a pet dragged into it
# asks with the delete popups.
class DesktopPetsTest < ApplicationSystemTestCase
  # Each test starts with the account's trash empty, the banana peel taken
  # out (banana_peel_test.rb).
  setup do
    @user = log_in_as("participant")
    @user.update!(desktop_trash: [], banana_peel_out: true)
    @rock = @user.projects.create!(name: "rock", description: "naps on your windows")
  end

  test "each pet is an icon that opens its pet page in a window of its own, and its ship button opens the pet's ship window" do
    goose = @user.projects.create!(name: "goose <b>honk</b>", screenshots: [ { "id" => "goose", "key" => "goose.png", "url" => "https://playground.hackclub-assets.com/goose.png" } ])
    visit root_path
    assert_equal [ "rock", "goose <b>honk</b>" ], all(".app.pet").map(&:text), "a name shows as typed, in the order made"
    # Every pet wears the file picture welcome.txt and guide.txt wear, screenshot or not.
    assert_equal [ true ], all(".app.pet .appicon").map { it[:src].include?("/landing/file-") }.uniq

    # The pet's icon may lie under ship.exe, which the login opened, so Enter opens it.
    icon("rock").send_keys(:enter)
    window = "#window-pet-#{@rock.id}"
    assert_selector "#{window} .headertext", exact_text: "rock"
    within_frame(find("#{window} iframe")) do
      assert_selector "h2", text: "rock"
      assert_text "naps on your windows"
      assert_no_selector ".meter-bar, .goal"
      # The window is the pet's own, so it has no way back to the dashboard.
      assert_no_link "← dashboard"
      click_link "ship"
    end
    # The pet's own ship window opens beside its window, as from ship.exe.
    assert_selector "#window-ship-#{@rock.id} .headertext", exact_text: "rock.ship"
    within_frame(find("#window-ship-#{@rock.id} iframe")) { assert_text "ship rock" }

    # One window per pet: a second click raises it, and another pet gets its own.
    # ship.exe from the login moves aside too, off the icons' top row.
    page.execute_script(<<~JS)
      document.querySelectorAll(".pet-window, .ship-window, [id='window-goal.exe']").forEach(win => Object.assign(win.style, { left: "760px", top: "40px" }))
    JS
    icon("rock").click
    icon("goose <b>honk</b>").click
    assert_selector ".pet-window", count: 2
    assert_selector "#window-pet-#{goose.id} .headertext", exact_text: "goose <b>honk</b>"
    within("#window-pet-#{goose.id} .windowheader") { click_button "close", enable_aria_label: true }
    icon("goose <b>honk</b>").click
    assert_selector ".pet-window", count: 2
  end

  test "a pet opened from ship.exe's list, by name or edit button, opens in its own window, and its page on its own keeps the way back" do
    visit root_path(open: "goal")
    within_frame(find(".ship-frame")) { click_link "rock" }
    within_frame(find("#window-pet-#{@rock.id} iframe")) do
      assert_selector "h2", text: "rock"
      assert_no_link "← dashboard"
    end
    within_frame(find(".ship-frame")) do
      assert_text "your pets"
      assert_no_selector "h2", text: "rock"
    end

    # Its edit button opens the edit page in the same window, and ship.exe
    # keeps the list.
    within_frame(find(".ship-frame")) { click_link "edit", href: edit_project_path(@rock) }
    within_frame(find("#window-pet-#{@rock.id} iframe")) { assert_selector "h2", text: "edit rock" }
    assert_selector ".pet-window", count: 1
    within_frame(find(".ship-frame")) { assert_text "your pets" }

    visit project_path(@rock)
    assert_link "← dashboard", href: dashboard_path
  end

  test "ship.exe holds the meter and the pets, and ?open=ship still opens it" do
    visit root_path(open: "ship")
    assert_selector "#window-goal\\.exe .headertext", exact_text: "ship.exe"
    within_frame(find(".ship-frame")) do
      assert_text "your meter"
      assert_text "your pets"
      assert_link "rock"
    end
    assert_current_path root_path
    assert_selector ".app", exact_text: "ship.exe"
    assert_no_selector ".app", exact_text: "goal.exe"
  end

  test "a pet made or renamed in a window shows on the desktop at once" do
    visit root_path(open: "goal")
    within_frame(find(".ship-frame")) do
      click_link "+ new pet"
      fill_in "project[name]", with: "cat"
      click_button "create pet"
    end
    # The new pet's page opens in its own window, and ship.exe goes back to
    # the dashboard, which lists it.
    assert_selector ".app.pet", exact_text: "cat"
    cat = @user.projects.find_by!(name: "cat")
    within_frame(find("#window-pet-#{cat.id} iframe")) { assert_selector "h2", text: "cat" }
    within_frame(find(".ship-frame")) { assert_link "cat" }

    within_frame(find("#window-pet-#{cat.id} iframe")) do
      click_link "edit"
      fill_in "project[name]", with: "cool cat"
      click_button "save"
      # Turbo shows its copy of the pet page from before the save, then the
      # saved page. Under the full suite's load the round trip can outlast
      # the default wait, and the last look then lands on the copy as it goes.
      assert_selector "h2", text: "cool cat", wait: 10
    end
    assert_selector ".app.pet", exact_text: "cool cat"
    assert_selector "#window-pet-#{cat.id} .headertext", exact_text: "cool cat"
  end

  test "an icon dragged onto the trash leaves the desktop, the can looks full, and its menu puts the icon back" do
    # Without ship.exe, which the login opened, the wallpaper takes the click below.
    forget_open_windows
    visit root_path
    empty = trash_picture
    drag "welcome.txt", onto: "trash"
    assert_no_selector ".app", exact_text: "welcome.txt"
    # The picture alone shows the can is full. The label stays "trash".
    assert_not_equal empty, trash_picture
    assert_includes trash_picture, "/landing/trash-full-"
    assert_equal "trash", icon("trash").text
    assert_account_trash [ "welcome.txt" ]

    # The menu opens at the pointer on a right click, and lists the icon.
    icon("trash").right_click
    within("#trash-menu") do
      assert_selector "[role=menuitem]", count: 1
      click_button "restore welcome.txt"
    end
    assert_no_selector "#trash-menu"
    assert_selector ".app", exact_text: "welcome.txt"
    assert_equal empty, trash_picture
    assert_equal "trash", icon("trash").text
    assert_account_trash []

    # A click opens the menu too, and an empty trash says so.
    icon("trash").click
    assert_selector "#trash-menu", text: "the trash is empty"
    page.driver.browser.action.move_to_location(600, 700).click.perform
    assert_no_selector "#trash-menu"
  end

  test "an icon that goes in the trash takes its open window with it, on a desktop and on a phone" do
    [ [ 1440, 900 ], [ 390, 844 ] ].each do |size|
      resize_viewport_to(*size) do
        forget_open_windows
        page.execute_script("localStorage.removeItem('playground-desktop-trash')")
        @user.update!(desktop_trash: [])
        visit root_path
        # On a phone welcome.txt opens over the trash can.
        find("#welcome .windowclose").send_keys(:enter)
        find(".app", exact_text: "guide.txt").send_keys(:enter)
        assert_selector "#window-guide\\.txt"
        # The guide's window, made short and moved to the top, leaves the trash can in reach.
        page.execute_script("(win => { win.classList.add('resized'); Object.assign(win.style, { top: '10px', height: '80px' }) })(document.getElementById('window-guide.txt'))")
        drag "guide.txt", onto: "trash"
        assert_no_selector ".app", exact_text: "guide.txt"
        assert_no_selector "#window-guide\\.txt", wait: 2
        assert_account_trash [ "guide.txt" ]
        # The saved windows drop it too, a moment later.
        page.document.synchronize do
          saved = page.evaluate_script("localStorage.getItem('playground-window-state:' + arguments[0])", @user.id.to_s).to_s
          raise Capybara::ExpectationNotMet, "guide.txt is still saved at #{size}" if saved.include?("guide.txt")
        end
      end
    end
  end

  test "the trash follows the account to another browser, and stays in this browser for a visitor" do
    visit root_path
    drag "guide.txt", onto: "trash"
    assert_account_trash [ "guide.txt" ]

    Capybara.using_session(:other_browser) do
      log_in_as("participant")
      assert_no_selector ".app", exact_text: "guide.txt"
      assert_selector ".app", exact_text: "welcome.txt"
    end

    # Logged out, the desktop is a visitor's, with its own trash in this browser.
    visit root_path(open: "goal")
    click_reloading_the_desktop { within_frame(find(".ship-frame")) { click_button "log out" } }
    assert_no_selector ".app.pet"
    assert_selector ".app", exact_text: "guide.txt"
    # Fulfillment keeps the key of its first label, Bounty. The visitor's
    # fresh trash held the banana peel already.
    drag "Fulfillment", onto: "trash"
    assert_equal [ "banana peel", "Bounty" ], page.evaluate_script("JSON.parse(localStorage.getItem('playground-desktop-trash'))")
    visit root_path
    assert_no_selector ".app", exact_text: "Fulfillment"
    assert_account_trash [ "guide.txt" ]
  end

  test "a pet dragged onto the trash asks with the delete popups over the desktop: a no puts it back, three yeses delete it" do
    visit root_path(open: "goal")
    within_frame(find(".ship-frame")) { assert_link "rock" }
    # ship.exe stays open, down and right, where its list can show the change.
    page.execute_script("Object.assign(document.getElementById('window-goal.exe').style, { left: '700px', top: '120px' })")
    drag "rock", onto: "trash"
    assert_no_selector ".app", exact_text: "rock"
    within_frame(find(".delete-frame")) do
      assert_equal [ "delete rock?", "are you sure you want to delete rock?", "really? rock will be gone forever." ],
                   all("dialog.popup[open] p").map(&:text)
      within(all("dialog.popup[open]")[1]) { click_button "no" }
    end
    assert_no_selector ".delete-frame", visible: true
    assert_selector ".app", exact_text: "rock"
    assert Project.exists?(@rock.id)

    drag "rock", onto: "trash"
    within_frame(find(".delete-frame")) do
      within(all("dialog.popup[open]")[2]) { click_button "delete it" }
      within(all("dialog.popup[open]")[0]) { click_button "delete" }
      within(all("dialog.popup[open]")[0]) { click_button "yes" }
    end
    assert_no_selector ".delete-frame", visible: true
    assert_no_selector ".app", exact_text: "rock"
    assert_not Project.exists?(@rock.id)
    within_frame(find(".ship-frame")) do
      assert_text "no pets yet."
    end
    assert_account_trash [], "a pet never waits in the trash"
  end

  test "a shipped pet dragged onto the trash says it cannot be deleted and comes back, and the sponsor never goes in" do
    @rock.ships.create!(user: @user)
    visit root_path
    # ship.exe, which the login opened, may lie over the pet's icon.
    find("#window-goal\\.exe .windowclose").send_keys(:enter)
    drag "rock", onto: "trash"
    within_frame(find(".delete-frame")) do
      assert_selector "dialog.popup[open]", count: 1
      assert_selector "dialog.popup[open] p", exact_text: "a shipped pet cannot be deleted"
      click_button "ok"
    end
    assert_no_selector ".delete-frame", visible: true
    assert_selector ".app", exact_text: "rock"
    assert Project.exists?(@rock.id)

    drag "armand.sponsor", onto: "trash"
    assert_selector ".app", exact_text: "armand.sponsor"
    assert_account_trash []
  end

  test "the trash menu works from the keyboard" do
    visit root_path
    drag "welcome.txt", onto: "trash"
    drag "guide.txt", onto: "trash"
    page.execute_script("document.querySelector('.app[data-key=trash]').focus()")
    page.driver.browser.switch_to.active_element.send_keys(:enter)
    assert_selector "#trash-menu"
    assert_equal "restore welcome.txt", page.evaluate_script("document.activeElement.textContent")
    page.driver.browser.switch_to.active_element.send_keys(:down)
    page.driver.browser.switch_to.active_element.send_keys(:down)
    assert_equal "restore all", page.evaluate_script("document.activeElement.textContent")
    page.driver.browser.switch_to.active_element.send_keys(:enter)
    assert_no_selector "#trash-menu"
    assert_selector ".app", exact_text: "welcome.txt"
    assert_selector ".app", exact_text: "guide.txt"
    assert_equal "trash", page.evaluate_script("document.activeElement.dataset.key")

    page.driver.browser.switch_to.active_element.send_keys(:enter)
    assert_selector "#trash-menu", text: "the trash is empty"
    page.driver.browser.switch_to.active_element.send_keys(:escape)
    assert_no_selector "#trash-menu"
  end

  private
    # The trash can by its key, as its label says when it is full.
    def icon(label)
      label == "trash" ? find(".app[data-key=trash]") : find(".app", exact_text: label)
    end

    def icon_center(label)
      box = page.evaluate_script("arguments[0].getBoundingClientRect().toJSON()", icon(label))
      [ (box["x"] + box["width"] / 2).round, (box["y"] + box["height"] / 2).round ]
    end

    # The desktop saves the account's trash in the background, so this waits
    # for the saved list to match.
    def assert_account_trash(icons, message = nil)
      deadline = Time.now + Capybara.default_max_wait_time
      sleep 0.05 until @user.reload.desktop_trash == icons || Time.now > deadline
      assert_equal icons, @user.desktop_trash, message
    end

    def trash_picture
      icon("trash").find(".appicon")[:src]
    end

    # Drags one icon onto another, with a first small move past the drag
    # threshold.
    def drag(label, onto:)
      x, y = icon_center(label)
      page.driver.browser.action.move_to_location(x, y).click_and_hold
        .move_to_location(x + 10, y + 10).move_to_location(*icon_center(onto)).release.perform
      assert_no_selector ".app.moving"
    end
end
