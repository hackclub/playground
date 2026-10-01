require "application_system_test_case"

# The rock goes into the trash like an icon: the can lights up while the rock
# is held over it, and lets go, the rock stops and shows nowhere, and the can
# looks full. The trash keeps it through a reload, in this browser for a
# visitor and on a participant's account, and puts it back on the floor.
class RockTrashTest < ApplicationSystemTestCase
  test "a visitor drops the rock in the trash, reloads, and puts it back" do
    # From an empty trash, the banana peel taken out (banana_peel_test.rb).
    visit root_path
    page.execute_script("localStorage.setItem('playground-desktop-trash', '[]'); localStorage.setItem('playground-banana-peel-out', '1')")
    visit root_path
    drop_rock_on_trash
    assert_equal [ "rock" ], page.evaluate_script("JSON.parse(localStorage.getItem('playground-desktop-trash'))")

    visit root_path
    assert_rock_in_trash
    restore_rock
    assert_equal [], page.evaluate_script("JSON.parse(localStorage.getItem('playground-desktop-trash'))")
  end

  test "a participant's trash keeps the rock on the account" do
    user = log_in_as "participant"
    user.update!(desktop_trash: [], banana_peel_out: true)
    visit root_path
    drop_rock_on_trash
    assert_account_trash user, [ "rock" ]

    visit root_path
    assert_rock_in_trash
    restore_rock
    assert_account_trash user, []
  end

  test "the rock let go beside the can falls to the floor as before" do
    visit root_path
    x, y = rock_center
    # Above the can, which stands in the bottom right corner.
    can = page.evaluate_script("(box => [box.left + box.width / 2, box.top - 120].map(Math.round))(document.querySelector('.app[data-key=trash]').getBoundingClientRect())")
    page.driver.browser.action.move_to_location(x, y).click_and_hold.move_to_location(x + 10, y - 10).move_to_location(*can).release.perform
    assert_selector "#desktop-pet.walking[style*='bottom: -9px']"
    assert_no_selector "#desktop-pet.in-trash", visible: :all
    assert_nil page.evaluate_script("localStorage.getItem('playground-desktop-trash')")
  end

  test "the rock let go on a window over the can lands, and stays out of the trash" do
    visit root_path
    page.execute_script(<<~JS)
      (can => Object.assign(document.getElementById("welcome").style, { left: `${can.left - 40}px`, top: `${can.top - 40}px` }))(document.querySelector(".app[data-key=trash]").getBoundingClientRect())
    JS
    x, y = rock_center
    can = page.evaluate_script("(box => [box.left + box.width / 2, box.top + box.height / 2].map(Math.round))(document.querySelector('.app[data-key=trash]').getBoundingClientRect())")
    assert_equal "welcome", page.evaluate_script("document.elementFromPoint(arguments[0], arguments[1]).closest('.window').id", *can)
    mouse = page.driver.browser.action
    mouse.move_to_location(x, y).click_and_hold.move_to_location(x + 10, y - 10).move_to_location(*can).perform
    assert_no_selector ".app[data-key=trash].drop-target"
    mouse.release.perform
    assert_selector "#desktop-pet.walking[style*='bottom: -9px']"
    assert_no_selector "#desktop-pet.in-trash", visible: :all
    assert_nil page.evaluate_script("localStorage.getItem('playground-desktop-trash')")
  end

  private
    # Wherever the rock shows now: walking, or its still frame when stopped.
    # Above its foot, which stands behind the taskbar's top edge.
    def rock_center
      page.evaluate_script(<<~JS)
        (() => {
          const shown = ["desktop-pet", "desktop-pet-static"].map(id => document.getElementById(id)).find(el => getComputedStyle(el).display !== "none")
          const box = shown.getBoundingClientRect()
          return [box.left + box.width / 2, box.top + box.height * 0.55].map(Math.round)
        })()
      JS
    end

    def drop_rock_on_trash
      x, y = rock_center
      can = page.evaluate_script("(box => [box.left + box.width / 2, box.top + box.height / 2].map(Math.round))(document.querySelector('.app[data-key=trash]').getBoundingClientRect())")
      mouse = page.driver.browser.action
      mouse.move_to_location(x, y).click_and_hold.move_to_location(x + 10, y - 10).move_to_location(*can).perform
      assert_selector ".app[data-key=trash].drop-target"
      mouse.release.perform
      assert_rock_in_trash
    end

    def assert_rock_in_trash
      assert_selector "#desktop-pet.in-trash", visible: :all
      assert_equal [ "none", "none" ], page.evaluate_script(<<~JS)
        ["desktop-pet", "desktop-pet-static"].map(id => getComputedStyle(document.getElementById(id)).display)
      JS
      assert_includes find(".app[data-key=trash] .appicon")[:src], "/landing/trash-full-"
      assert_no_selector ".app[data-key=trash].drop-target"
    end

    def restore_rock
      find(".app[data-key=trash]").click
      within("#trash-menu") { click_button "restore rock" }
      assert_selector "#desktop-pet.walking[style*='bottom: -9px']"
      assert_no_selector "#desktop-pet.in-trash", visible: :all
      assert_includes find(".app[data-key=trash] .appicon")[:src], "/landing/trash-empty-"
    end

    def assert_account_trash(user, icons)
      deadline = Time.now + Capybara.default_max_wait_time
      sleep 0.05 until user.reload.desktop_trash == icons || Time.now > deadline
      assert_equal icons, user.desktop_trash
    end
end
