require "application_system_test_case"

# The trash can's menu closes as soon as the participant turns to a window:
# a press inside a window's frame, which the desktop hears only as its own
# window losing focus, or a window that opens or comes to the front. So it
# never stays drawn over a window.
class TrashMenuClosesTest < ApplicationSystemTestCase
  test "a click inside a framed pet window closes the menu, which never shows over the window" do
    user = log_in_as "participant"
    rock = user.projects.create!(name: "rock")
    forget_open_windows
    visit root_path
    find(".app", exact_text: "rock").click
    win = "#window-pet-#{rock.id}"
    within_frame(find("#{win} iframe")) { assert_text "rock" }
    # The pet window off to the right, clear of the can.
    page.execute_script("Object.assign(document.querySelector(arguments[0]).style, { left: '700px', top: '120px' })", win)

    open_menu
    x, y = page.evaluate_script("(box => [box.left + box.width / 2, box.top + box.height / 2].map(Math.round))(document.querySelector(arguments[0] + ' iframe').getBoundingClientRect())", win)
    page.driver.browser.action.move_to_location(x, y).click.perform
    assert_no_selector "#trash-menu"
    assert_menu_not_over win
  end

  test "opening a window closes the menu, and the menu never shows over the window" do
    forget_open_windows
    visit root_path
    open_menu
    find(".app", exact_text: "guide.txt").click
    assert_selector "#window-guide\\.txt"
    assert_no_selector "#trash-menu"
    assert_menu_not_over "#window-guide\\.txt"
  end

  private
    def open_menu
      find(".app[data-key=trash]").right_click
      assert_selector "#trash-menu", text: "restore banana peel"
    end

    # Nothing of the menu lies above the window: at the window's middle, and
    # wherever the menu last stood, the window's own element is on top.
    def assert_menu_not_over(win)
      on_top = page.evaluate_script(<<~JS, win)
        (win => {
          const menu = document.getElementById("trash-menu"), box = win.getBoundingClientRect()
          const points = [[box.left + box.width / 2, box.top + box.height / 2],
            [parseFloat(menu.style.left) + 8, parseFloat(menu.style.top) + 8]]
          return points.filter(([x, y]) => x > box.left && x < box.right && y > box.top && y < box.bottom)
            .every(([x, y]) => win.contains(document.elementFromPoint(x, y)))
        })(document.querySelector(arguments[0]))
      JS
      assert on_top, "the window shows over where the menu was"
    end
end
