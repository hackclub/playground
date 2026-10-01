require "application_system_test_case"

# The trash can's menu keeps its white items inside its blue frame, 4px in
# from every side, whatever it lists. Opened at the screen's right edge, it
# opens inward, whole and with no line wrapped.
class TrashMenuTest < ApplicationSystemTestCase
  EVERY_ICON = [ "welcome.txt", "guide.txt", "goal.exe", "Hack Club", "Terms & Privacy", "Bounty", "Security" ].freeze

  test "the menu's items sit inside its frame, empty, with one icon, or with every icon, and at the right edge" do
    [ [ 1440, 900 ], [ 390, 844 ] ].each do |width, height|
      resize_browser_to(width, height) do
        [ [], [ "Bounty" ], EVERY_ICON ].each do |trash|
          at = "#{trash.size} in the trash at #{width}px"
          visit root_path
          page.execute_script("localStorage.setItem('playground-desktop-trash', JSON.stringify(arguments[0]))", trash)
          visit root_path
          close_welcome
          find(".app[data-key=trash]").click
          from_can = menu_fit
          assert_equal({ "inside" => true, "sides" => [ 4, 4 ], "ends" => [ 4, 4 ] }, from_can.except("height"), at)
          send_keys :escape

          # Moved to the grid's last column, the can opens the menu under the pointer, by the edge.
          columns = find("#apps", visible: :all)["data-grid"].split.first.to_i
          page.execute_script("localStorage.setItem('playground-desktop-icons', JSON.stringify({ trash: [arguments[0] - 1, 1] }))", columns)
          visit root_path
          close_welcome
          find(".app[data-key=trash]").right_click
          at_edge = menu_fit
          assert_equal from_can, at_edge, "at the right edge, #{at}"
          page.execute_script("localStorage.removeItem('playground-desktop-icons')")
        end
      end
    end
  end

  private
    # On a phone welcome.txt opens over the icons. A reload keeps it closed.
    # login.exe opens with each load, over welcome.txt's X, so it closes first.
    def close_welcome
      close_login_window
      within("#welcome .windowheader") { click_button "close", enable_aria_label: true } if page.has_selector?("#welcome", wait: false)
      assert_no_selector "#welcome"
    end

    # Whether the menu lies inside the screen, each item's inset from the
    # frame's left and right sides, the first and last items' insets from its
    # top and bottom, and its height.
    def menu_fit
      assert_selector "#trash-menu"
      page.evaluate_script(<<~JS)
        (menu => {
          const box = menu.getBoundingClientRect(), root = document.documentElement
          const items = [...menu.children].map(item => item.getBoundingClientRect())
          const sides = [...new Set(items.map(item => `${Math.round(item.left - box.left)},${Math.round(box.right - item.right)}`))]
          return {
            inside: box.left >= 0 && box.top >= 0 && box.right <= root.clientWidth && box.bottom <= root.clientHeight,
            sides: sides.length === 1 ? sides[0].split(",").map(Number) : sides,
            ends: [Math.round(items[0].top - box.top), Math.round(box.bottom - items.at(-1).bottom)],
            height: Math.round(box.height)
          }
        })(document.getElementById("trash-menu"))
      JS
    end
end
