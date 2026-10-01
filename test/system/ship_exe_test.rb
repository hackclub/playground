require "application_system_test_case"

# The window with the dashboard is ship.exe. For a while it was goal.exe, and
# it keeps that name as its key, so a desktop saved then still finds it: its
# icon's spot, its window's spot, the window open at a reload, and the trash,
# in this browser and on a participant's account. A pet's own ship window,
# such as rock.ship, is another window. A visitor's ship.exe opens the login,
# login.exe, instead.
class ShipExeTest < ApplicationSystemTestCase
  test "the icon, the title bar, and the frame say ship.exe" do
    log_in_as "participant"
    visit root_path
    find(".app", exact_text: "ship.exe").send_keys(:enter)
    assert_selector "#window-goal\\.exe .headertext", exact_text: "ship.exe"
    assert_equal "ship.exe", find(".ship-frame")["title"]
    assert_no_text "goal.exe"
  end

  test "a desktop saved while it was goal.exe gets ship.exe back in its saved spot, open where it was" do
    user = log_in_as "participant"
    # As the desktop saved them then, under the old name, from a page that
    # saves none. The spot lies between the bottom groups, as a window that
    # comes back by itself never covers the required links.
    visit dashboard_path
    page.execute_script(<<~JS, "playground-window-state:#{user.id}")
      localStorage.setItem("playground-desktop-icons", JSON.stringify({ "goal.exe": [6, 4] }))
      localStorage.setItem(arguments[0], JSON.stringify([
        { kind: "goal", id: null, page: "/dashboard", place: { left: 330, top: 60 } }
      ]))
    JS
    visit root_path
    assert_equal "6,4", find(".app", exact_text: "ship.exe")["data-cell"]
    assert_selector "#window-goal\\.exe .headertext", exact_text: "ship.exe"
    assert_no_selector "#welcome"
    assert_equal [ 330, 60 ], settled_spot("window-goal.exe")

    # Closed, it opens from its icon at the spot saved for its window.
    visit dashboard_path
    page.execute_script(<<~JS, "playground-window-state:#{user.id}")
      localStorage.setItem(arguments[0], "[]")
      localStorage.setItem("playground-window-places", JSON.stringify({ "window-goal.exe": { left: 400, top: 60 } }))
    JS
    visit root_path
    assert_no_selector "#window-goal\\.exe"
    find(".app", exact_text: "ship.exe").send_keys(:enter)
    assert_equal [ 400, 60 ], settled_spot("window-goal.exe")
  end

  test "a trash saved while it was goal.exe still holds ship.exe, in this browser and on the account" do
    visit dashboard_path
    page.execute_script("localStorage.setItem('playground-desktop-trash', JSON.stringify(['goal.exe']))")
    visit root_path
    assert_no_selector ".app", exact_text: "ship.exe"
    find(".app[data-key=trash]").click
    assert_selector "#trash-menu [role=menuitem]", exact_text: "restore ship.exe"

    user = log_in_as "participant"
    # The banana peel taken out, so the trash holds only goal.exe.
    user.update!(desktop_trash: [ "goal.exe" ], banana_peel_out: true)
    visit root_path
    assert_no_selector ".app", exact_text: "ship.exe"
    find(".app[data-key=trash]").click
    click_button "restore ship.exe"
    assert_selector ".app", exact_text: "ship.exe"
    deadline = Time.now + Capybara.default_max_wait_time
    sleep 0.05 until user.reload.desktop_trash.empty? || Time.now > deadline
    assert_empty user.desktop_trash
  end

  test "ship.exe and a pet's rock.ship open together, and both come back after a reload" do
    user = log_in_as "participant"
    rock = user.projects.create!(name: "rock")
    visit root_path
    assert_selector "#window-goal\\.exe"
    # The pet's icon may lie under ship.exe, which the login opened, so Enter opens it.
    find(".app", exact_text: "rock").send_keys(:enter)
    within_frame(find("#window-pet-#{rock.id} iframe")) { click_link "ship" }
    assert_selector "#window-ship-#{rock.id} .headertext", exact_text: "rock.ship"
    assert_selector "#window-goal\\.exe .headertext", exact_text: "ship.exe"
    # ship.exe's icon raises ship.exe, not the ship window.
    find(".app", exact_text: "ship.exe").send_keys(:enter)
    assert_equal "window-goal.exe", front_window

    visit root_path
    within_frame(find("#window-goal\\.exe iframe")) { assert_text "your pets" }
    within_frame(find("#window-ship-#{rock.id} iframe")) { assert_text "ship rock" }
    assert_selector "#window-goal\\.exe .headertext", exact_text: "ship.exe"
    assert_selector "#window-ship-#{rock.id} .headertext", exact_text: "rock.ship"
  end

  private
    # Where a window sits once it has been placed.
    def settled_spot(id)
      page.document.synchronize do
        raise Capybara::ExpectationNotMet, "#{id} is still being placed" if page.evaluate_script("!!document.getElementById(arguments[0]).dataset.placing", id)
      end
      page.evaluate_script("(win => [win.offsetLeft, win.offsetTop])(document.getElementById(arguments[0]))", id)
    end

    def front_window
      page.evaluate_script(<<~JS)
        [...document.querySelectorAll(".window")].filter(win => getComputedStyle(win).display !== "none")
          .sort((a, b) => getComputedStyle(a).zIndex - getComputedStyle(b).zIndex).pop().id
      JS
    end
end
