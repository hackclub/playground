require "application_system_test_case"

# The desktop ends at the taskbar's top edge, and the taskbar shows whole, as
# a desktop's stays on top. Windows open, fit, come back, and resize above
# it. A drag may take a window's body under it, but the part under it is cut
# off, so "gulp" and "gulp2" still show and take clicks.
class TaskbarTest < ApplicationSystemTestCase
  SIZES = [ [ 1440, 900 ], [ 1024, 768 ], [ 390, 844 ] ].freeze

  setup do
    @user = log_in_as("participant")
    @rock = @user.projects.create!(name: "rock", description: "a pebble that naps on your windows all day long")
  end

  test "after a login, ship.exe ends at the taskbar's top, and the taskbar shows whole" do
    SIZES.each do |size|
      resize_viewport_to(*size) do
        forget_open_windows
        log_in_as("participant")
        within_frame(find(".ship-frame")) { assert_text "your meter" }
        assert_above_taskbar size
      end
    end
  end

  test "a pet's window on its edit page and its ship window end above the taskbar" do
    SIZES.each do |size|
      resize_viewport_to(*size) do
        forget_open_windows
        visit root_path
        find(".app", exact_text: "rock").send_keys(:enter)
        within_frame(find("#window-pet-#{@rock.id} iframe")) { find_link("ship").send_keys(:enter) }
        within_frame(find("#window-ship-#{@rock.id} iframe")) { assert_text "ship rock" }
        within_frame(find("#window-pet-#{@rock.id} iframe")) { find_link("edit").send_keys(:enter) }
        within_frame(find("#window-pet-#{@rock.id} iframe")) { assert_selector "h2", text: "edit rock" }
        assert_above_taskbar size
      end
    end
  end

  test "a spot or a size saved under the taskbar comes back above it, moved, not dropped" do
    forget_open_windows
    visit root_path
    bar = taskbar_top
    # welcome.txt's spot and a height taller than the desktop, and ship.exe's
    # spot in the open windows a reload brings back, both under the taskbar,
    # and both between the bottom groups, clear of the required links. They
    # are written from a page that saves no windows.
    visit dashboard_path
    page.execute_script(<<~JS, bar, "playground-window-state:#{@user.id}")
      localStorage.setItem("playground-window-places", JSON.stringify({ welcome: { left: 400, top: 100, width: 500, height: 3000 } }))
      localStorage.setItem(arguments[1], JSON.stringify([
        { kind: "app", id: "welcome.txt" },
        { kind: "goal", page: "/dashboard", place: { left: 330, top: arguments[0] - 40 } }
      ]))
    JS
    visit root_path
    within_frame(find(".ship-frame")) { assert_text "your meter" }
    page.document.synchronize { raise Capybara::ExpectationNotMet, "ship.exe is placing" if page.evaluate_script("!!document.getElementById('window-goal.exe').dataset.placing") }
    assert_above_taskbar
    assert_equal 400, window_box("#welcome")["left"]
    assert_equal 330, window_box("#window-goal\\.exe")["left"]
    # welcome.txt's saved height shrank to the desktop's.
    desktop_top = page.evaluate_script("parseFloat(getComputedStyle(document.documentElement).getPropertyValue('--desktop-top'))")
    assert_in_delta bar - desktop_top, window_box("#welcome")["height"], 1
  end

  test "a resize from the bottom edge stops at the taskbar" do
    forget_open_windows
    visit root_path
    # welcome.txt's text runs far longer than the screen.
    page.execute_script("Object.assign(document.getElementById('welcome').style, { left: '700px', top: '200px' })")
    box = window_box("#welcome")
    x, y = (box["left"] + box["width"] / 2).round, (box["bottom"] - 2).round
    height = page.evaluate_script("innerHeight")
    page.driver.browser.action.move_to_location(x, y).click_and_hold.move_to_location(x, height - 1).release.perform
    assert_in_delta taskbar_top, window_box("#welcome")["bottom"], 1
    assert_above_taskbar
  end

  # At the suite's 1440x900 browser window the page is 757px tall, with the
  # taskbar's top at 717px.
  test "a window that ends flush on the taskbar still resizes from each bottom handle" do
    forget_open_windows
    visit root_path
    # welcome.txt's text runs far longer than the screen, so grown down it
    # stops flush on the taskbar.
    welcome_at_own_size
    page.execute_script("Object.assign(document.getElementById('welcome').style, { left: '500px', top: '100px' })")
    height = page.evaluate_script("innerHeight")
    { s: [ 0, -60 ], se: [ 40, -60 ], sw: [ -40, -60 ] }.each do |edge, (dx, dy)|
      box = window_box("#welcome")
      drag_handle edge, box, to: [ nil, height - 1 ]
      flush = window_box("#welcome")
      assert_in_delta taskbar_top, flush["bottom"], 1, "welcome.txt ends on the taskbar before the #{edge} drag"
      assert_equal "", page.evaluate_script("document.getElementById('welcome').style.clipPath"), "nothing is cut off"
      drag_handle edge, flush, by: [ dx, dy ]
      moved = window_box("#welcome")
      assert_in_delta flush["bottom"] + dy, moved["bottom"], 1, "the #{edge} handle moves the bottom"
      assert_in_delta flush["width"] + dx.abs, moved["width"], 1, "the #{edge} handle moves its side" unless dx.zero?
      assert_taskbar_shows
    end
  end

  test "a window dragged down goes under the taskbar, its header stays above it, and the taskbar still takes clicks" do
    forget_open_windows
    visit root_path
    header = find("#welcome .headertext")
    x, y = page.evaluate_script("(box => [Math.round(box.left + 20), Math.round(box.top + box.height / 2)])(arguments[0].getBoundingClientRect())", header)
    height = page.evaluate_script("innerHeight")
    page.driver.browser.action.move_to_location(x, y).click_and_hold.move_to_location(x, height - 1).release.perform

    bar = taskbar_top
    window = window_box("#welcome")
    assert_operator window["bottom"], :>, bar, "the window's body is under the taskbar"
    assert_operator window_box("#welcome .windowheader")["bottom"], :<=, bar, "the header stays above it"
    # The part under the taskbar is cut off: the taskbar takes a press there.
    assert_equal "bar", page.evaluate_script("document.elementFromPoint(arguments[0], arguments[1]).closest('#bar')?.id", x, (bar + [ window["bottom"], height - 1 ].min) / 2)
    assert_taskbar_shows
  end

  test "the trash menu opens above the taskbar" do
    visit root_path
    rows = find("#apps", visible: :all)["data-grid"].split.last.to_i
    page.execute_script("localStorage.setItem('playground-desktop-icons', JSON.stringify({ trash: [0, arguments[0] - 1] }))", rows)
    visit root_path
    trash = find(".app[data-key=trash]")
    x, y = page.evaluate_script("(box => [Math.round(box.left + box.width / 2), Math.round(box.bottom - 4)])(arguments[0].getBoundingClientRect())", trash)
    page.driver.browser.action.move_to_location(x, y).context_click.perform
    # A fresh trash holds the banana peel.
    assert_selector "#trash-menu", text: "restore banana peel"
    assert_operator window_box("#trash-menu")["bottom"], :<=, taskbar_top + 0.5
    assert_taskbar_shows
  end

  private

  def taskbar_top = page.evaluate_script("document.getElementById('bar').getBoundingClientRect().top")

  # Drags one of welcome.txt's bottom handles, 2px inside its frame, by an
  # offset or to a point. A nil in the point keeps that axis.
  def drag_handle(edge, box, by: nil, to: nil)
    x = { s: box["left"] + box["width"] / 2, se: box["right"] - 2, sw: box["left"] + 2 }.fetch(edge).round
    y = (box["bottom"] - 2).round
    target = to ? [ to[0] || x, to[1] || y ] : [ x + by[0], y + by[1] ]
    page.driver.browser.action.move_to_location(x, y).click_and_hold.move_to_location(*target).release.perform
  end

  def window_box(selector)
    page.evaluate_script("document.querySelector(arguments[0]).getBoundingClientRect().toJSON()", selector)
  end

  # Once every open window is placed, each one's bottom edge is at or above
  # the taskbar's top, and the taskbar's words show.
  def assert_above_taskbar(size = nil)
    page.document.synchronize do
      raise Capybara::ExpectationNotMet, "a window is still being placed" if page.evaluate_script("!!document.querySelector('.window[data-placing]')")
    end
    bar = taskbar_top
    bottoms = page.evaluate_script(<<~JS)
      [...document.querySelectorAll(".window")].filter(w => getComputedStyle(w).display !== "none")
        .map(w => [w.id, w.getBoundingClientRect().bottom])
    JS
    assert_not_empty bottoms
    bottoms.each { |id, bottom| assert_operator bottom, :<=, bar + 0.5, "#{id} ends above the taskbar#{" at #{size}" if size}" }
    assert_taskbar_shows(size)
  end

  # A press on the middle of "gulp" or "gulp2" lands on the word.
  def assert_taskbar_shows(size = nil)
    shown = page.evaluate_script(<<~JS)
      [...document.querySelectorAll("#bar button")].map(word => {
        const box = word.getBoundingClientRect()
        return [word.textContent.trim(), word.contains(document.elementFromPoint(box.left + box.width / 2, box.top + box.height / 2))]
      })
    JS
    assert_equal [ [ "gulp", true ], [ "gulp2", true ] ], shown, "the taskbar shows whole#{" at #{size}" if size}"
  end
end
