require "application_system_test_case"

# The banana peel is in the trash, so the can looks full, unless this visitor
# or account took it out themselves: in a fresh trash, and in one saved
# before the peel came. The rest of a saved trash stays as it was. Put back,
# the peel is an icon that opens nothing, and it goes back in the trash like
# any icon.
class BananaPeelTest < ApplicationSystemTestCase
  test "a first-time visitor's trash holds the peel, which comes out and goes back in" do
    visit root_path
    page.execute_script("localStorage.clear()")
    visit root_path
    # The peel comes out at the right edge, where login.exe may lie.
    close_login_window
    assert_includes can_picture, "/landing/trash-full-"
    assert_no_selector ".app", exact_text: "banana peel"
    assert_nil stored_trash, "a fresh trash saves nothing until it changes"

    sponsor = find(".app[data-key='armand.sponsor']")["data-cell"]
    find(".app[data-key=trash]").click
    within("#trash-menu") do
      assert_equal [ "restore banana peel" ], all("[role=menuitem]").map(&:text)
      click_button "restore banana peel"
    end
    peel = find(".app", exact_text: "banana peel")
    assert_includes peel.find(".appicon")[:src], "/landing/banana-peel-"
    assert_includes can_picture, "/landing/trash-empty-"
    assert_equal [], stored_trash
    assert_equal sponsor, find(".app[data-key='armand.sponsor']")["data-cell"], "the sponsor keeps its spot"

    # It opens nothing.
    windows = all(".window", visible: true).size
    peel.double_click
    peel.send_keys(:enter)
    assert_equal windows, all(".window", visible: true).size

    drag peel, onto: find(".app[data-key=trash]")
    assert_no_selector ".app", exact_text: "banana peel"
    assert_includes can_picture, "/landing/trash-full-"
    assert_equal [ "banana peel" ], stored_trash

    visit root_path
    assert_no_selector ".app", exact_text: "banana peel"
    assert_includes can_picture, "/landing/trash-full-"
  end

  test "a browser's trash saved before the peel came holds it, and keeps the rest" do
    visit root_path
    page.execute_script("localStorage.clear()")
    page.execute_script("localStorage.setItem('playground-desktop-trash', '[]')")
    visit root_path
    assert_includes can_picture, "/landing/trash-full-"
    assert_no_selector ".app", exact_text: "banana peel"

    page.execute_script("localStorage.setItem('playground-desktop-trash', JSON.stringify(['guide.txt']))")
    visit root_path
    assert_no_selector ".app", exact_text: "guide.txt"
    find(".app[data-key=trash]").click
    within("#trash-menu") { assert_equal [ "restore guide.txt", "restore banana peel", "restore all" ], all("[role=menuitem]").map(&:text) }
  end

  test "a browser that took the peel out keeps it out through a reload, until it goes back in" do
    visit root_path
    page.execute_script("localStorage.clear()")
    visit root_path
    # The peel comes out at the right edge, where login.exe may lie.
    close_login_window
    find(".app[data-key=trash]").click
    within("#trash-menu") { click_button "restore banana peel" }
    assert_selector ".app", exact_text: "banana peel"

    visit root_path
    assert_selector ".app", exact_text: "banana peel"
    assert_includes can_picture, "/landing/trash-empty-"

    drag find(".app", exact_text: "banana peel"), onto: find(".app[data-key=trash]")
    assert_nil page.evaluate_script("localStorage.getItem('playground-banana-peel-out')")
    visit root_path
    assert_no_selector ".app", exact_text: "banana peel"
    assert_includes can_picture, "/landing/trash-full-"
  end

  test "a new account's trash holds the peel, and taking it out keeps it out" do
    user = log_in_as "participant"
    assert_equal [ "banana peel" ], user.desktop_trash
    visit root_path
    assert_includes can_picture, "/landing/trash-full-"
    find(".app[data-key=trash]").click
    within("#trash-menu") { click_button "restore banana peel" }
    assert_selector ".app", exact_text: "banana peel"
    assert_account user, [], out: true

    # ship.exe, open since the login, would lie over the peel at the right edge.
    forget_open_windows
    visit root_path
    assert_selector ".app", exact_text: "banana peel"
    assert_includes can_picture, "/landing/trash-empty-"

    drag find(".app", exact_text: "banana peel"), onto: find(".app[data-key=trash]")
    assert_account user, [ "banana peel" ], out: false
  end

  test "an existing account whose trash is empty, or holds other icons, holds the peel as well" do
    user = log_in_as "participant"
    user.update!(desktop_trash: [])
    visit root_path
    assert_includes can_picture, "/landing/trash-full-"
    assert_no_selector ".app", exact_text: "banana peel"

    user.update!(desktop_trash: [ "guide.txt" ])
    visit root_path
    assert_no_selector ".app", exact_text: "guide.txt"
    find(".app[data-key=trash]").click
    within("#trash-menu") { assert_equal [ "restore guide.txt", "restore banana peel", "restore all" ], all("[role=menuitem]").map(&:text) }
    assert_equal [ "guide.txt" ], user.reload.desktop_trash, "loading the desktop writes nothing"
  end

  private
    def can_picture = find(".app[data-key=trash] .appicon")[:src]

    def stored_trash = page.evaluate_script("JSON.parse(localStorage.getItem('playground-desktop-trash'))")

    # Drags one icon onto another, with a first small move past the drag
    # threshold.
    def drag(icon, onto:)
      from, to = [ icon, onto ].map { page.evaluate_script("(box => [box.left + box.width / 2, box.top + 40].map(Math.round))(arguments[0].getBoundingClientRect())", it) }
      page.driver.browser.action.move_to_location(*from).click_and_hold
        .move_to_location(from[0] + 12, from[1] + 12).move_to_location(*to).release.perform
      assert_no_selector ".app.moving"
    end

    # The account's saved trash, and whether it records the peel as taken out.
    def assert_account(user, icons, out:)
      deadline = Time.now + Capybara.default_max_wait_time
      sleep 0.05 until [ user.reload.desktop_trash, user.banana_peel_out ] == [ icons, out ] || Time.now > deadline
      assert_equal [ icons, out ], [ user.desktop_trash, user.banana_peel_out ]
    end
end
