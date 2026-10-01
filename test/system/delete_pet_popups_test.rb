require "application_system_test_case"

# The delete button on the edit page opens three popups at once. The pet is
# deleted only when all three are confirmed, in any order. Any cancel, any X,
# or Escape closes them all and deletes nothing. Each drags by its title bar.
class DeletePetPopupsTest < ApplicationSystemTestCase
  MESSAGES = [ "delete rock?", "are you sure you want to delete rock?", "really? rock will be gone forever." ].freeze

  setup do
    @project = log_in_as("participant").projects.create!(name: "rock", description: "naps on your windows")
  end

  teardown { page.current_window.resize_to(1440, 900) }

  test "confirming all three popups, in any order, deletes the pet" do
    visit edit_project_path(@project)
    click_button "delete pet"
    assert_selector "dialog.popup[open][role=alertdialog]", count: 3
    assert_equal MESSAGES, all("dialog.popup[open] p").map(&:text)
    assert_equal [ 340 ], popup_boxes.map { it["width"] }.uniq, "the popups share one fixed width"
    assert_equal [ "none" ], page.evaluate_script("[...document.querySelectorAll('dialog.popup')].map((p) => getComputedStyle(p).resize)").uniq

    within(popup(2)) { click_button "delete it" }
    assert_selector "dialog.popup[open]", count: 2
    within(popup(0)) { click_button "delete" }
    assert_selector "dialog.popup[open]", count: 1
    within(popup(1)) { click_button "yes" }

    assert_current_path dashboard_path
    assert_text "no pets yet."
    assert_not Project.exists?(@project.id)
  end

  test "confirming two popups and cancelling the third deletes nothing and keeps what was typed" do
    visit edit_project_path(@project)
    fill_in "name", with: "renamed rock"
    click_button "delete pet"
    within(popup(0)) { click_button "delete" }
    within(popup(1)) { click_button "yes" }
    within(popup(2)) { click_button "keep it" }

    assert_no_selector "dialog.popup[open]"
    assert_field "name", with: "renamed rock"
    assert_equal "delete pet", page.evaluate_script("document.activeElement.textContent")
    assert_current_path edit_project_path(@project)
    assert Project.exists?(@project.id)
  end

  test "the X, Escape, and a press on the page behind delete nothing, and a double-click opens one set" do
    visit edit_project_path(@project)
    find_button("delete pet").double_click
    assert_selector "dialog.popup[open]", count: 3
    assert_selector "dialog.popup", count: 3, visible: :all

    # The page behind is inert: a press on it neither focuses it nor closes the popups.
    page.driver.browser.action.move_to_location(40, 40).click.perform
    assert_selector "dialog.popup[open]", count: 3
    assert page.evaluate_script("!!document.activeElement.closest('dialog.popup[open]')")

    within(popup(1)) { click_button "close", enable_aria_label: true }
    assert_no_selector "dialog.popup[open]"

    click_button "delete pet"
    within(popup(0)) { click_button "delete" }
    page.send_keys(:escape)
    assert_no_selector "dialog.popup[open]"
    assert_no_selector "[inert]"
    assert Project.exists?(@project.id)
  end

  test "by keyboard, focus starts on the top popup's safe choice and Tab stays in the popups" do
    visit edit_project_path(@project)
    find_button("delete pet").send_keys(:enter)
    assert_selector "dialog.popup[open]", count: 3
    assert_focused "cancel"

    9.times do
      page.send_keys(:tab)
      assert page.evaluate_script("!!document.activeElement.closest('dialog.popup[open]')"), "focus stays in the popups"
    end
    assert_focused "cancel"

    # Focus raised each popup in turn, so the first is on top, then the third.
    page.send_keys([ :shift, :tab ])
    assert_focused "delete"
    page.send_keys(:enter)
    assert_selector "dialog.popup[open]", count: 2
    assert_focused "keep it"
    page.send_keys([ :shift, :tab ], :enter)
    assert_selector "dialog.popup[open]", count: 1
    assert_focused "no"
    page.send_keys([ :shift, :tab ], :enter)

    assert_current_path dashboard_path
    assert_not Project.exists?(@project.id)
  end

  test "a popup drags by its title bar and comes to the front, and all three open in their stack again" do
    visit edit_project_path(@project)
    click_button "delete pet"
    stack = popup_boxes.map { it.values_at("left", "top") }

    # The top popup moves by its title bar, and the others stay put.
    drag_title 0, by: [ -400, 250 ]
    assert_equal [ stack[0][0] - 400, stack[0][1] + 250 ], popup_boxes[0].values_at("left", "top")
    assert_equal stack.drop(1), popup_boxes.drop(1).map { it.values_at("left", "top") }

    # The second popup's title bar shows now. A drag brings it to the front.
    drag_title 1, by: [ 300, -150 ]
    assert_equal [ stack[1][0] + 300, stack[1][1] - 150 ], popup_boxes[1].values_at("left", "top")
    assert_operator z_index(1), :>, z_index(0), "the dragged popup comes to the front"

    # A press on the X that moves off drags nothing. A click closes all three.
    close = page.evaluate_script("(b => [b.x + b.width / 2, b.y + b.height / 2].map(Math.round))(document.querySelectorAll('dialog.popup[open]')[1].querySelector('.popup-close').getBoundingClientRect())")
    page.driver.browser.action.move_to_location(*close).click_and_hold.move_to_location(close[0] - 100, close[1] + 100).release.perform
    assert_equal [ stack[1][0] + 300, stack[1][1] - 150 ], popup_boxes[1].values_at("left", "top")
    within(popup(1)) { click_button "close", enable_aria_label: true }
    assert_no_selector "dialog.popup[open]"

    click_button "delete pet"
    assert_equal stack, popup_boxes.map { it.values_at("left", "top") }
    assert Project.exists?(@project.id)
  end

  test "in the pet's window on a phone, the popups fit the frame, and the delete closes the window and shows ship.exe's list" do
    page.current_window.resize_to(390, 844)
    visit root_path(open: "goal")
    within_frame(find(".ship-frame")) { click_link "edit" }
    window = "#window-pet-#{@project.id}"
    within_frame(find("#{window} iframe")) do
      click_button "delete pet"
      assert_selector "dialog.popup[open]", count: 3
      width, height = page.evaluate_script("[innerWidth, innerHeight]")
      popup_boxes.each do |box|
        assert box["left"] >= 0 && box["top"] >= 0 && box["right"] <= width && box["bottom"] <= height, "#{box} fits #{width}x#{height}"
      end

      # A finger drags the top popup by its title bar, inside the frame.
      top = popup_boxes[0]
      finger = Selenium::WebDriver::Interactions.pointer(:touch, name: "finger")
      frame = page.evaluate_script("window.frameElement.getBoundingClientRect().toJSON()")
      from = [ frame["left"] + top["left"] + 60, frame["top"] + top["top"] + 14 ].map(&:round)
      page.driver.browser.action(devices: [ finger ]).move_to_location(*from).pointer_down(:left)
        .move_to_location(from[0] + 20, from[1] + 120).pointer_up(:left).perform
      assert_equal [ top["left"] + 20, top["top"] + 120 ], popup_boxes[0].values_at("left", "top")

      # It lies over the others now, so it goes first.
      within(popup(0)) { click_button "delete" }
      within(popup(1)) { click_button "yes" }
      within(popup(2)) { click_button "delete it" }
    end
    assert_no_selector window
    assert_no_selector ".app.pet"
    within_frame(find(".ship-frame")) { assert_text "no pets yet." }
    assert_not Project.exists?(@project.id)
  end

  private

  # "delete rock?" is also the end of the second message, so the whole message must match.
  def popup(index) = find("dialog.popup[open]") { it.has_css?("p", exact_text: MESSAGES[index], wait: false) }

  def popup_boxes = page.evaluate_script("[...document.querySelectorAll('dialog.popup[open]')].map((p) => p.getBoundingClientRect().toJSON())")

  # Holds a popup's title bar 60px in from its left end.
  def drag_title(index, by:)
    title = page.evaluate_script("document.querySelectorAll('dialog.popup[open]')[arguments[0]].querySelector('.popup-head').getBoundingClientRect().toJSON()", index)
    from = [ title["left"] + 60, title["top"] + 10 ].map(&:round)
    page.driver.browser.action.move_to_location(*from).click_and_hold.move_to_location(from[0] + by[0], from[1] + by[1]).release.perform
  end

  def z_index(index) = page.evaluate_script("Number(document.querySelectorAll('dialog.popup[open]')[arguments[0]].style.zIndex)", index)

  def assert_focused(text)
    assert_equal text, page.evaluate_script("document.activeElement.textContent.trim()")
  end
end
