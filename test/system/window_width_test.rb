require "application_system_test_case"

# A window can't be dragged wider than its content can use: the width at
# which its longest line and widest picture fit, and no more than 720px. It
# may always be as wide as it opens. A restored width past that shrinks to
# it, and the left edge stays put.
class WindowWidthTest < ApplicationSystemTestCase
  setup { resize_viewport_to(1440, 900) }

  test "text windows stop at 720px, and the guide opens there" do
    visit root_path
    assert_equal 720, drag_wider("#welcome")

    open_icon "guide.txt"
    assert_equal 720, width("#window-guide\\.txt")
    assert_equal 720, drag_wider("#window-guide\\.txt")
  end

  test "the left edge and the corners stop there too, at 1024x768 as well" do
    [ [ 1440, 900 ], [ 1024, 768 ] ].each do |size|
      resize_viewport_to(*size)
      forget_open_windows
      visit root_path
      # login.exe may lie where welcome.txt goes.
      close_login_window
      # drag_wider moves welcome.txt to the right margin first.
      right = page.evaluate_script("document.documentElement.clientWidth") - 10
      assert_equal 720, drag_wider("#welcome", edge: :w), "at #{size}"
      assert_equal right, box("#welcome")["right"], "the right edge stays put at #{size}"
      place "#welcome", left: 20
      assert_equal 720, drag_wider("#welcome", edge: :se), "at #{size}"
    end
  end

  test "a pet window stops where its screenshot fits, and ship.exe at the width it opens" do
    user = log_in_as("participant")
    pet = user.projects.create!(name: "rock pet", description: "a rock that naps")
    # An 1100x620 screenshot, as in the report of the empty band, inline.
    wide = "data:image/png;base64,#{Base64.strict_encode64(image_bytes(1100, 620))}"
    pet.update_columns(screenshots: [ { "id" => "wide", "key" => "wide.png", "url" => wide } ])
    visit root_path
    open_icon "pet-#{pet.id}"
    window = "#window-pet-#{pet.id}"
    within_frame(find("#{window} iframe")) { assert_selector "img.shot" }

    drag_wider(window)
    band = within_frame(find("#{window} iframe")) do
      page.evaluate_script("(shot => document.documentElement.clientWidth - shot.getBoundingClientRect().right)(document.querySelector('img.shot'))")
    end
    assert_operator band, :<=, 40, "no empty band right of the screenshot"
    within_frame(find("#{window} iframe")) do
      assert_equal 360, page.evaluate_script("Math.round(document.querySelector('img.shot').getBoundingClientRect().height)"), "the screenshot shows at its full height"
    end

    open_icon "goal.exe"
    assert_equal 620, drag_wider("#window-goal\\.exe")
  end

  test "a pet window with several screenshots stops where the widest fits, whichever shows" do
    user = log_in_as("participant")
    pet = user.projects.create!(name: "rock pet", description: "a rock that naps")
    tall = "data:image/png;base64,#{Base64.strict_encode64(image_bytes(900, 1200))}"
    wide = "data:image/png;base64,#{Base64.strict_encode64(image_bytes(1100, 620))}"
    pet.update_columns(screenshots: [ { "id" => "tall", "key" => "tall.png", "url" => tall }, { "id" => "wide", "key" => "wide.png", "url" => wide } ])
    visit root_path
    open_icon "pet-#{pet.id}"
    window = "#window-pet-#{pet.id}"
    # The cover is the narrow one, and the wide one sets the width.
    within_frame(find("#{window} iframe")) { assert_selector ".carousel img.shot[alt^='screenshot 1 of 2']:not([aria-hidden])" }
    drag_wider(window)
    within_frame(find("#{window} iframe")) do
      band = page.evaluate_script("(box => document.documentElement.clientWidth - box.getBoundingClientRect().right)(document.querySelector('.carousel'))")
      assert_operator band, :<=, 40, "no empty band right of the carousel"
      click_button "next screenshot", enable_aria_label: true
      assert_equal 360, page.evaluate_script("Math.round(document.querySelector('.shot:not([aria-hidden])').getBoundingClientRect().height)"),
                   "the wide screenshot shows at its full height"
    end
  end

  test "a ship window stops at 720px at most" do
    user = log_in_as("participant")
    user.update!(hackatime_access_token: "fake")
    pet = user.projects.create!(name: "rock")
    visit root_path
    open_icon "pet-#{pet.id}"
    within_frame(find("#window-pet-#{pet.id} iframe")) { find_link("ship").send_keys(:enter) }
    window = "#window-ship-#{pet.id}"
    within_frame(find("#{window} iframe")) { assert_selector "#ship-checks li" }
    opens = width(window)
    widest = drag_wider(window)
    assert_operator widest, :<=, 720
    assert_operator widest, :>=, opens
    assert_equal widest, drag_wider(window), "a second drag gains nothing"
  end

  test "a saved width past the limit comes back at the limit, left edge kept" do
    # With no open windows saved, which would bring welcome.txt back where it last was.
    forget_open_windows
    page.execute_script("localStorage.setItem('playground-window-places', JSON.stringify({ welcome: { left: 100, top: 60, width: 1200, height: 300 } }))")
    visit root_path
    assert_equal [ 100, 60, 720 ], box("#welcome").values_at("left", "top", "width")
  end

  private

  def open_icon(key)
    find(".app[data-key='#{key}']").send_keys(:enter)
    assert_selector "#window-#{key.gsub(".", "\\.")}"
    page.document.synchronize { raise Capybara::ExpectationNotMet, "#{key} is placing" if page.evaluate_script("!!document.getElementById('window-#{key}').dataset.placing") }
  end

  def box(selector) = page.evaluate_script("(b => ({ left: Math.round(b.left), top: Math.round(b.top), right: Math.round(b.right), width: Math.round(b.width) }))(document.querySelector(arguments[0]).getBoundingClientRect())", selector)
  def width(selector) = box(selector)["width"]

  def place(selector, left:)
    page.execute_script("document.querySelector(arguments[0]).style.left = arguments[1] + 'px'", selector, left)
  end

  # Drags the right edge, the left edge, or the bottom right corner as far
  # as the screen lets it go, and returns the width the window stops at.
  def drag_wider(selector, edge: :e)
    place selector, left: 20 unless edge == :w
    page.execute_script("document.querySelector(arguments[0]).style.left = (document.documentElement.clientWidth - document.querySelector(arguments[0]).offsetWidth - 10) + 'px'", selector) if edge == :w
    b = page.evaluate_script("(b => b.toJSON())(document.querySelector(arguments[0]).getBoundingClientRect())", selector)
    screen = page.evaluate_script("document.documentElement.clientWidth")
    from, to = case edge
    when :e then [ [ b["right"] - 2, b["top"] + 60 ], [ screen - 5, b["top"] + 60 ] ]
    when :w then [ [ b["left"] + 2, b["top"] + 60 ], [ 5, b["top"] + 60 ] ]
    when :se then [ [ b["right"] - 6, b["bottom"] - 6 ], [ screen - 5, b["bottom"] - 6 ] ]
    end
    page.driver.browser.action.move_to_location(*from.map(&:round)).click_and_hold.move_to_location(*to.map(&:round)).release.perform
    width(selector)
  end
end
