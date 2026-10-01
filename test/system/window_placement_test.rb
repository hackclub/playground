require "application_system_test_case"

# Where a desktop window opens. The first time, where it covers the least of
# the icons and the open windows. After a move or a resize, where it was left,
# in this browser, if that still fits the screen. With nothing free, a step
# down and right of the last window. A window that opens with the page never
# covers the sponsor's icon. Phones, where windows fill the width, keep the
# old layout. A visitor's desktop opens login.exe beside welcome.txt.
class WindowPlacementTest < ApplicationSystemTestCase
  # Every test sets the viewport itself: the browser window's own size leaves
  # less of it to the page. The login's height sets where login.exe fits.
  setup do
    resize_viewport_to(1440, 900)
    without_hack_club_app
  end

  # welcome.txt opens large, from under the tagline to the taskbar, clear of
  # the icons. login.exe opens with it, at its right, 10px off and level with
  # its top, where the screen has room, as on a large one. Elsewhere it slides
  # left over welcome.txt, in front, only as far as it must to fit and to keep
  # clear of the icons, the sponsor's icon, the logo, and its line. At
  # 1000x600 it is too tall to, and stops above the bottom groups too.
  test "the first windows open clear of the icons, with login.exe beside welcome.txt" do
    [ [ 1920, 1080 ], [ 1440, 900 ], [ 1280, 720 ], [ 1024, 768 ], [ 1000, 600 ] ].each do |size|
      resize_viewport_to(*size)
      forget_open_windows
      visit root_path
      assert_selector "#welcome"
      assert_clear_of_icons "#welcome", size
      assert_clear_of "#welcome", sponsor_icon, "the sponsor's icon shows at #{size}"

      assert_selector "#window-login\\.exe"
      settled
      login, welcome = box("#window-login\\.exe"), box("#welcome")
      assert_equal welcome["top"], login["top"], "level with welcome.txt at #{size}"
      assert_operator login["left"], :<=, welcome["right"] + 10, "at #{size}"
      assert_operator login["right"], :<=, page.evaluate_script("document.documentElement.clientWidth") - 10, "on the screen at #{size}"
      assert_clear_of_icons "#window-login\\.exe", size
      assert_clear_of "#window-login\\.exe", sponsor_icon, "the sponsor's icon shows at #{size}"
      %w[.background-logo .background-logo-text].each { assert_clear_of "#window-login\\.exe", box(it), "#{it} shows at #{size}" }
      assert_equal "window-login.exe", front_window, "login.exe is in front at #{size}"
      if size == [ 1920, 1080 ]
        assert_equal welcome["right"] + 10, login["left"], "side by side at #{size}"
      else
        # 10px further right would leave the screen or cover something kept clear.
        assert_not_empty covered_by(login.merge("left" => login["left"] + 10, "right" => login["right"] + 10)), "slid only as far as it must at #{size}"
      end
    end
  end

  # With welcome.txt closed, login.exe goes beside where welcome.txt opens.
  test "with welcome.txt closed, login.exe opens beside where welcome.txt would" do
    visit root_path
    settled
    beside = box("#window-login\\.exe").values_at("left", "top")
    # Its X may lie under login.exe, so it closes by keyboard.
    find("#welcome .windowclose").send_keys(:enter)
    visit root_path
    assert_no_selector "#welcome"
    assert_selector "#window-login\\.exe"
    settled
    assert_equal beside, box("#window-login\\.exe").values_at("left", "top")
  end

  # Too tall to sit level with welcome.txt, here a login page taller than
  # the desktop below the tagline, login.exe stops 10px above what lies below
  # that line, level with welcome.txt still, clear of every icon, the
  # sponsor's icon, the logo, and its line, and its page scrolls inside.
  test "a login.exe too tall to sit beside welcome.txt stops above the icons, level with it, and its page scrolls" do
    tall = page.driver.browser.execute_cdp("Page.addScriptToEvaluateOnNewDocument", source: <<~JS)
      if (location.pathname === "/login") addEventListener("DOMContentLoaded", () => { document.body.style.paddingBottom = "300px" })
    JS
    [ [ 1440, 900 ], [ 1024, 768 ], [ 1000, 600 ] ].each do |size|
      resize_viewport_to(*size)
      forget_open_windows
      visit root_path
      assert_selector "#window-login\\.exe"
      settled
      login, welcome = box("#window-login\\.exe"), box("#welcome")
      assert_equal welcome["top"], login["top"], "level with welcome.txt at #{size}"
      scrolls = page.evaluate_script(<<~JS)
        (win => win.querySelector(".login-frame").contentDocument.body.getBoundingClientRect().height > win.querySelector(".windowcontent").clientHeight + 100)(document.getElementById("window-login.exe"))
      JS
      assert scrolls, "its page scrolls inside at #{size}"
      assert_clear_of_icons "#window-login\\.exe", size
      %w[.background-logo .background-logo-text].each { assert_clear_of "#window-login\\.exe", box(it), "#{it} shows at #{size}" }
      assert_clear_of "#window-login\\.exe", sponsor_icon, "the sponsor's icon shows at #{size}"
    end
  ensure
    page.driver.browser.execute_cdp("Page.removeScriptToEvaluateOnNewDocument", identifier: tall["identifier"]) if tall
  end

  # Every other window that opens with the page goes where it covers the
  # least of the icons and the open windows, icons or not, clear of the
  # sponsor's icon, and where the text row of the required links is hidden,
  # of their four icons: here ship.exe after a login. Too tall to fit above
  # them, it may stop above them, at the height it ends up.
  test "after a login, ship.exe opens with the page where it covers the least, as ever" do
    [ [ 1440, 900 ], [ 1280, 720 ], [ 1024, 768 ] ].each do |size|
      resize_viewport_to(*size)
      forget_open_windows
      log_in_as("participant")
      assert_selector "#window-goal\\.exe"
      settled
      spot = box("#window-goal\\.exe").values_at("left", "top")
      least = least_covered_spot("#window-goal\\.exe")
      assert_in_delta least[0], spot[0], 1, "at #{size}"
      assert_in_delta least[1], spot[1], 1, "at #{size}"
      click_reloading_the_desktop { within_frame(find(".ship-frame")) { click_button "log out" } }
    end
  end

  test "after login, welcome.txt and ship.exe leave the sponsor's icon showing" do
    resize_viewport_to(1024, 768)
    log_in_as("participant")
    assert_selector "#window-goal\\.exe"
    page.document.synchronize { raise Capybara::ExpectationNotMet, "ship.exe is placing" if page.evaluate_script("!!document.getElementById('window-goal.exe').dataset.placing") }
    %w[#welcome #window-goal\\.exe].each { assert_clear_of it, sponsor_icon, "#{it} leaves the sponsor's icon showing" }
  end

  test "a window moved or resized opens where it was left, after a reload too" do
    visit root_path
    settled
    # Above the bottom right group: login.exe comes back with every load, and
    # it would not come back over the required links.
    drag_header "#window-login\\.exe", to: [ 700, 150 ]
    spot = box("#window-login\\.exe").values_at("left", "top")
    resize_bottom "#welcome", by: -150
    welcome = box("#welcome").values_at("left", "top", "width", "height")

    within("#window-login\\.exe .windowheader") { click_button "close", enable_aria_label: true }
    open_icon "goal.exe", window: "login.exe"
    assert_equal spot, box("#window-login\\.exe").values_at("left", "top")

    # Closed, it comes back with the next load, where it was left.
    within("#window-login\\.exe .windowheader") { click_button "close", enable_aria_label: true }
    visit root_path
    assert_equal welcome, box("#welcome").values_at("left", "top", "width", "height")
    assert_selector "#window-login\\.exe"
    settled
    assert_equal spot, box("#window-login\\.exe").values_at("left", "top")
  end

  test "a saved spot that no longer fits the screen gives way to a free spot" do
    visit root_path
    settled
    width = page.evaluate_script("document.documentElement.clientWidth")
    # Against the right margin, where it fits whole here but not at 1024px.
    drag_header "#window-login\\.exe", to: [ width - 530, 300 ]
    saved = box("#window-login\\.exe")
    assert_operator saved["right"], :<=, width

    resize_viewport_to(1024, 768)
    visit root_path
    assert_selector "#window-login\\.exe"
    settled
    moved = box("#window-login\\.exe")
    assert_not_equal saved.values_at("left", "top"), moved.values_at("left", "top")
    assert_operator moved["right"], :<=, page.evaluate_script("document.documentElement.clientWidth")
    assert_clear_of_icons "#window-login\\.exe", [ 1024, 768 ]
  end

  # guide.txt is tall, so at its full height every spot covers some icon. A
  # pet saved in the middle of the desktop would be the least of them. The
  # window stops above the icons instead, and the pet stays in sight.
  test "a window opened by a click stops above the icons rather than cover a pet" do
    # The browser window's own page, 1440x757, as most tests have it.
    page.driver.browser.execute_cdp("Emulation.clearDeviceMetricsOverride")
    user = log_in_as("participant")
    rock = user.projects.create!(name: "rock", description: "naps on your windows")
    forget_open_windows
    visit root_path
    page.execute_script("localStorage.setItem('playground-desktop-icons', JSON.stringify({ [arguments[0]]: [4, 3] }))", "pet-#{rock.id}")
    visit root_path
    page.execute_script("document.querySelectorAll('.window').forEach(win => { if (getComputedStyle(win).display !== 'none') win.querySelector('.windowclose').click() })")
    open_icon "guide.txt"
    page.document.synchronize do
      raise Capybara::ExpectationNotMet, "guide.txt is still being placed" if page.evaluate_script("!!document.querySelector('.window[data-placing]')")
    end
    assert_clear_of_icons "#window-guide\\.txt", [ 1440, 757 ]
    rock_box = box(".app[data-key='pet-#{rock.id}']")
    assert_equal "pet-#{rock.id}", page.evaluate_script("document.elementFromPoint(arguments[0], arguments[1]).closest('.app')?.dataset.key",
      (rock_box["left"] + rock_box["width"] / 2).round, (rock_box["top"] + 30).round)
  end

  # A participant's desktop, which opens no login.exe, and ship.exe opened
  # from its icon, as a window not opened with the page.
  test "with no free spot, windows cascade a step down and right" do
    log_in_as("participant")
    forget_open_windows
    visit root_path
    assert_selector "#welcome"
    # welcome.txt stretched over the whole desktop, so every spot covers it.
    page.execute_script(<<~JS)
      (() => {
        const top = document.getElementById("credits").getBoundingClientRect().bottom
        Object.assign(document.getElementById("welcome").style, {
          left: "10px", top: top + "px", maxWidth: "none", maxHeight: "none",
          width: document.documentElement.clientWidth - 20 + "px", height: document.documentElement.clientHeight - top - 10 + "px"
        })
      })()
    JS
    welcome = box("#welcome")
    open_icon "guide.txt"
    guide = box("#window-guide\\.txt")
    assert_equal [ welcome["left"] + 30, welcome["top"] + 30 ], guide.values_at("left", "top")
    open_icon "goal.exe"
    assert_equal [ guide["left"] + 30, guide["top"] + 30 ], box("#window-goal\\.exe").values_at("left", "top")
  end

  test "on a phone, windows open as before and nothing is saved" do
    resize_viewport_to(390, 844)
    visit root_path
    open_icon "guide.txt"
    assert_equal 10, box("#window-guide\\.txt")["left"]
    drag_header "#window-guide\\.txt", to: [ 100, 500 ]
    assert_nil page.evaluate_script("localStorage.getItem('playground-window-places')")
  end

  private

  # An icon opens from the keyboard, so a window lying over it doesn't matter.
  # A visitor's ship.exe opens another window, login.exe.
  def open_icon(key, window: key)
    find(".app[data-key='#{key}']").send_keys(:enter)
    assert_selector "#window-#{window.gsub(".", "\\.")}"
    settled
  end

  # The window at the front.
  def front_window
    page.evaluate_script(<<~JS)
      [...document.querySelectorAll(".window")].filter(w => getComputedStyle(w).display !== "none")
        .sort((a, b) => getComputedStyle(a).zIndex - getComputedStyle(b).zIndex).pop().id
    JS
  end

  # What a box would cover of what login.exe keeps clear of: the icons' drawn
  # pictures and labels, the sponsor's icon, and where their text row is
  # hidden, the four required links' icons, the logo, and its line, and the
  # screen's 10px margin at the right.
  def covered_by(box)
    page.evaluate_script(<<~JS, box)
      (box => {
        const bounds = JSON.parse(document.getElementById("apps").dataset.iconBounds || "{}")
        const hit = b => Math.min(box.right, b.right) > Math.max(box.left, b.left) && Math.min(box.bottom, b.bottom) > Math.max(box.top, b.top)
        const row = getComputedStyle(document.getElementById("credit-links")).display === "none"
        const icons = [...document.querySelectorAll("#apps .app")].filter(icon => icon.offsetParent).filter(icon => {
          const picture = icon.querySelector(".appicon"), shown = picture.getBoundingClientRect()
          const [l, t, r, b] = bounds[picture.getAttribute("src")] ?? [0, 0, 1, 1]
          const drawn = { left: shown.left + l * shown.width, top: shown.top + t * shown.height, right: shown.left + r * shown.width, bottom: shown.top + b * shown.height }
          const kept = icon.dataset.key === "armand.sponsor" || (row && ["Hack Club", "Terms & Privacy", "Bounty", "Security"].includes(icon.dataset.key))
          return hit(drawn) || hit(icon.querySelector("p").getBoundingClientRect()) || (kept && hit(icon.getBoundingClientRect()))
        }).map(icon => icon.dataset.key)
        const logo = [".background-logo", ".background-logo-text"].filter(selector => hit(document.querySelector(selector).getBoundingClientRect()))
        return [...icons, ...logo, ...(box.right > document.documentElement.clientWidth - 10 ? ["the right margin"] : [])]
      })(arguments[0])
    JS
  end

  def settled
    page.document.synchronize do
      raise Capybara::ExpectationNotMet, "a window is still being placed" if page.evaluate_script("!!document.querySelector('.window[data-placing]')")
    end
  end

  def box(selector) = page.evaluate_script("(b => ({ left: Math.round(b.left), top: Math.round(b.top), right: Math.round(b.right), bottom: Math.round(b.bottom), width: Math.round(b.width), height: Math.round(b.height) }))(document.querySelector(arguments[0]).getBoundingClientRect())", selector)

  def sponsor_icon = box(".app[data-key='armand.sponsor']")

  # The spot, on the desktop's 10px grid, where the window would cover the
  # least of the icons' drawn pictures and labels and the other open windows,
  # clear of the sponsor's icon, and of the four required links' icons where
  # their text row is hidden: from the top down, and from the right.
  def least_covered_spot(selector)
    page.evaluate_script(<<~JS, selector)
      (selector => {
        const win = document.querySelector(selector), root = document.documentElement
        const bounds = JSON.parse(document.getElementById("apps").dataset.iconBounds || "{}")
        const rect = b => ({ left: b.left, top: b.top, width: b.right - b.left, height: b.bottom - b.top })
        const icons = [...document.querySelectorAll("#apps .app")].filter(icon => icon.offsetParent).flatMap(icon => {
          const picture = icon.querySelector(".appicon"), shown = picture.getBoundingClientRect()
          const [l, t, r, b] = bounds[picture.getAttribute("src")] ?? [0, 0, 1, 1]
          const drawn = { left: shown.left + l * shown.width, top: shown.top + t * shown.height, right: shown.left + r * shown.width, bottom: shown.top + b * shown.height }
          return [rect(drawn), rect(icon.querySelector("p").getBoundingClientRect())]
        })
        const windows = [...document.querySelectorAll(".window")].filter(other => other !== win && getComputedStyle(other).display !== "none")
          .map(other => rect(other.getBoundingClientRect()))
        const row = getComputedStyle(document.getElementById("credit-links")).display === "none"
        const kept = ["armand.sponsor", ...(row ? ["Hack Club", "Terms & Privacy", "Bounty", "Security"] : [])]
          .map(key => rect(document.querySelector(`.app[data-key="${key}"]`).getBoundingClientRect()))
        const area = (a, b) => {
          const w = Math.min(a.left + a.width, b.left + b.width) - Math.max(a.left, b.left)
          const h = Math.min(a.top + a.height, b.top + b.height) - Math.max(a.top, b.top)
          return w > 0 && h > 0 ? w * h : 0
        }
        const steps = (from, to) => {
          if (to <= from) return [from]
          const values = []
          for (let value = from; value < to; value += 10) values.push(value)
          return values.concat(to)
        }
        const top = document.getElementById("credits").getBoundingClientRect().bottom
        const bottom = document.getElementById("bar").getBoundingClientRect().top
        const width = win.offsetWidth, height = win.offsetHeight
        let best = null
        for (const y of steps(top, bottom - height)) {
          for (const x of steps(10, root.clientWidth - 10 - width).reverse()) {
            const box = { left: x, top: y, width, height }
            if (kept.some(icon => area(box, icon) > 0)) continue
            const covered = [...icons, ...windows].reduce((sum, other) => sum + area(box, other), 0)
            if (!best || covered < best.covered) best = { x, y, covered }
          }
        }
        return [best.x, best.y]
      })(arguments[0])
    JS
  end

  def overlap(a, b) = [ [ a["right"], b["right"] ].min - [ a["left"], b["left"] ].max, 0 ].max * [ [ a["bottom"], b["bottom"] ].min - [ a["top"], b["top"] ].max, 0 ].max

  def assert_clear_of(selector, other, message)
    assert_equal 0, overlap(box(selector), other), message
  end

  # The window covers no icon's drawn picture or label.
  def assert_clear_of_icons(selector, size)
    covered = page.evaluate_script(<<~JS, selector)
      (selector => {
        const bounds = JSON.parse(document.getElementById("apps").dataset.iconBounds || "{}")
        const win = document.querySelector(selector).getBoundingClientRect()
        const hit = (b) => Math.min(win.right, b.right) > Math.max(win.left, b.left) && Math.min(win.bottom, b.bottom) > Math.max(win.top, b.top)
        return [...document.querySelectorAll("#apps .app")].filter((icon) => icon.offsetParent).filter((icon) => {
          const picture = icon.querySelector(".appicon"), shown = picture.getBoundingClientRect()
          const [l, t, r, b] = bounds[picture.getAttribute("src")] ?? [0, 0, 1, 1]
          const drawn = { left: shown.left + l * shown.width, top: shown.top + t * shown.height, right: shown.left + r * shown.width, bottom: shown.top + b * shown.height }
          return hit(drawn) || hit(icon.querySelector("p").getBoundingClientRect())
        }).map((icon) => icon.dataset.key)
      })(arguments[0])
    JS
    assert_empty covered, "#{selector} covers icons at #{size}"
  end

  def drag_header(selector, to:)
    b = box("#{selector} .windowheader")
    from = [ b["left"] + 60, b["top"] + 10 ]
    page.driver.browser.action.move_to_location(*from).click_and_hold.move_to_location(to[0] + 60, to[1] + 10).release.perform
  end

  def resize_bottom(selector, by:)
    b = box(selector)
    x, y = b["left"] + b["width"] / 2, b["bottom"] - 2
    page.driver.browser.action.move_to_location(x, y).click_and_hold.move_to_location(x, y + by).release.perform
  end
end
