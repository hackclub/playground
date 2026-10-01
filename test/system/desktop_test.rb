require "application_system_test_case"

# froppii's desktop in a real browser: ship.exe opens the dashboard in its
# window, or for a visitor the login in login.exe, a dev login lands back on
# the desktop with ship.exe open, and the desktop never renders inside a
# window.
class DesktopTest < ApplicationSystemTestCase
  # Hack Club's required links, by the label on each icon.
  REQUIRED_LINKS = {
    "Hack Club" => "https://hackclub.com",
    "Terms & Privacy" => "https://hackclub.com/privacy-and-terms",
    "Fulfillment" => "https://forms.hackclub.com/bounty",
    "Security" => "https://security.hackclub.com"
  }.freeze

  test "a visitor's ship.exe opens the login, and logging in opens it on the dashboard" do
    visit root_path
    assert_selector "#welcome .headertext", text: "welcome.txt"
    # A first visit opens login.exe too. It may open in the corner below, so
    # it closes.
    within("#window-login\\.exe .windowheader") { click_button "close", enable_aria_label: true }
    assert_equal "https://hackclub.slack.com/archives/C0ASBTMS82H", find("#welcome a", exact_text: "#playground")[:href]
    assert_no_text "playground-ysws"
    # armand.sponsor is the only credit. At this size the required links are
    # icons, so the credits hold nothing, and their corner takes a press as
    # the wallpaper does.
    assert_no_text "sponsored by"
    # welcome.txt opens in that corner, clear of the icons, so it moves aside.
    page.execute_script("document.getElementById('welcome').style.top = '300px'")
    assert_equal find("body"), page.evaluate_script("document.elementFromPoint(innerWidth - 14, 14)")
    flag = find("#flag-link")
    assert_equal "https://hackclub.com/", flag[:href]
    assert_equal flag, page.evaluate_script("document.elementFromPoint(100, 40)"), "a click on the flag lands on the link"

    find(".app", text: "ship.exe").click
    within_frame(find(".login-frame")) { assert_text "ship your desktop pet" }
    assert_no_selector "#window-goal\\.exe", visible: :all
    click_reloading_the_desktop { within_frame(find(".login-frame")) { click_link "participant" } }

    assert_current_path root_path
    within_frame(find(".ship-frame")) do
      assert_text "your meter"
      assert_selector ".goal", count: Goal.all.size
    end
  end

  test "a fresh visitor's ship.exe opens the login with no alert" do
    visit root_path
    find(".app", text: "ship.exe").click
    within_frame(find(".login-frame")) do
      assert_text "ship your desktop pet"
      assert_no_selector ".flash"
    end
    assert_no_selector "#window-goal\\.exe", visible: :all
  end

  # The desktop asks for the pets as data each time a window loads a page.
  # After the login ends, that request gets a 401, not a "log in first" that
  # would wait for the next page.
  test "a desktop whose login ended elsewhere leaves no alert for the login" do
    user = log_in_as("participant")
    user.projects.create!(name: "rock")
    visit root_path
    assert_selector ".app.pet", exact_text: "rock"
    user.increment!(:session_version)
    status = page.evaluate_async_script("fetch('/projects', { headers: { Accept: 'application/json' } }).then(response => arguments[0](response.status))")
    assert_equal 401, status

    visit root_path
    assert_no_selector ".app.pet"
    find(".app", text: "ship.exe").click
    within_frame(find(".login-frame")) do
      assert_text "ship your desktop pet"
      assert_no_selector ".flash"
    end
  end

  test "the required links are desktop icons that a click or Enter opens in a new tab, and a double-click opens once" do
    visit root_path
    # At this size the icons are the only copy, clear of the rock and welcome.txt.
    assert_no_selector "#credit-links"
    assert page.evaluate_script(<<~JS), "a click on each link icon lands on it"
      [...document.querySelectorAll("a.app")].every(icon => {
        const box = icon.querySelector(".appicon").getBoundingClientRect()
        return icon.contains(document.elementFromPoint(box.x + box.width / 2, box.y + box.height / 2))
      })
    JS

    # The four pictures, and the sponsor's face after them, are 128px square,
    # and every icon, the trash can too, shows at one size.
    sizes = page.evaluate_async_script(<<~JS)
      const done = arguments[arguments.length - 1]
      const icons = [...document.querySelectorAll(".appicon")]
      Promise.all(icons.map(icon => icon.decode())).then(() => done(icons.map(icon => [icon.naturalWidth, icon.width, icon.height])))
    JS
    assert_equal 10, sizes.size
    assert_equal [ [ 64, 64 ] ], sizes.map { |_, width, height| [ width, height ] }.uniq
    assert_equal [ 128 ], sizes[-6..-2].map(&:first).uniq

    # A listener after the icon's own notes whether each click would follow
    # the link, then stops it, which keeps the test off the network.
    page.execute_script(<<~JS)
      window.followed = []
      document.addEventListener("click", event => {
        if (!event.target.closest("a.app")) return
        window.followed.push(!event.defaultPrevented)
        event.preventDefault()
      })
    JS
    # Each click lands on another icon, so the browser counts none of them
    # as part of a double-click.
    REQUIRED_LINKS.each do |label, url|
      icon = find("a.app", exact_text: label)
      assert_equal [ URI(url).normalize.to_s, "_blank", "noopener" ], [ icon[:href], icon[:target], icon[:rel] ]
      icon.click
    end
    REQUIRED_LINKS.each_key do |label|
      icon = find("a.app", exact_text: label)
      icon.double_click
      icon.send_keys(:enter)
    end
    # A click follows the link. Of a double-click's two clicks only the first
    # does. Enter follows it too.
    assert_equal [ true ] * 4 + [ true, false, true ] * 4, page.evaluate_script("window.followed")
    assert_equal 1, windows.size
    assert_current_path root_path
  end

  test "where the icons can fall off the screen or start covered, the required links also show as text" do
    [ [ 390, 844 ], [ 844, 390 ], [ 1024, 768 ] ].each do |width, height|
      resize_browser_to(width, height) do
        visit root_path
        # On a phone the row stands in for the link icons and credits the
        # sponsor. On a desktop the icons show too, and his icon is the credit.
        assert_selector "a.app", count: width < 561 ? 0 : 5
        assert_equal width < 561, page.has_text?("sponsored by Armand", wait: 0), "the row's credit at #{width}x#{height}"
        assert_credit_links "at #{width}x#{height}"
      end
    end
  end

  test "without scripts, the required links and the sponsor's credit show as text" do
    page.driver.browser.execute_cdp("Emulation.setScriptExecutionDisabled", value: true)
    visit root_path
    assert_no_selector ".app"
    assert_text "sponsored by Armand"
    assert_equal ApplicationHelper::SPONSOR_URL, find("#credit-links a", exact_text: "Armand")[:href]
    assert_credit_links "without scripts"
  ensure
    page.driver.browser.execute_cdp("Emulation.setScriptExecutionDisabled", value: false)
  end

  test "the example pets in welcome.txt line up" do
    visit root_path
    # Wait for the pictures: at their own shapes they differ in height.
    page.evaluate_async_script(<<~JS)
      const done = arguments[arguments.length - 1]
      Promise.all([...document.querySelectorAll("#welcome .grid-image")].map(image => image.decode())).then(() => done())
    JS
    measure = <<~JS
      [...document.querySelectorAll("#welcome .image-card")].map(card => {
        const image = card.querySelector(".grid-image").getBoundingClientRect()
        const title = card.querySelector(".image-title").getBoundingClientRect()
        return [image.width, image.height, image.top, title.top].map(Math.round)
      })
    JS
    cards = page.evaluate_script(measure)
    assert_equal 4, cards.size
    assert_equal 1, cards.map { |width, height| [ width, height ] }.uniq.size, "every picture shows at one size"
    cards.group_by { |card| card[2] }.each_value do |row|
      assert_equal 1, row.map(&:last).uniq.size, "the titles in a row start on one line"
    end

    # A picture that has not loaded yet still holds its place.
    page.execute_script("document.querySelector('#welcome .grid-image').removeAttribute('src')")
    assert_equal cards, page.evaluate_script(measure)
  end

  test "the desktop leaves any frame it lands in" do
    visit root_path(open: "goal")
    within_frame(find(".login-frame")) { assert_text "ship your desktop pet" }

    # Point login.exe's frame at the desktop, as a stray redirect would. The
    # mark goes away with the old page, so the frame found below is the new one.
    page.execute_script("document.body.dataset.old = 'true'")
    page.execute_script("document.querySelector('.login-frame').src = '/?open=goal'")
    assert_no_selector "body[data-old]"

    # The whole window becomes the desktop, with login.exe showing the login again.
    within_frame(find(".login-frame")) do
      assert_text "ship your desktop pet"
      assert_no_selector "#welcome"
    end
    assert_selector "#welcome", count: 1
  end

  test "a press anywhere in a window brings it to the front" do
    visit root_path
    assert_selector "#welcome"
    find(".app", text: "ship.exe").click
    within_frame(find(".login-frame")) { assert_text "ship your desktop pet" }
    assert_no_selector ".window[data-placing]"

    # The two windows overlap around (830, 250), inside login.exe, which is as
    # tall as the login page. login.exe opened last, so it starts in front.
    page.execute_script(<<~JS)
      Object.assign(document.getElementById("window-login.exe").style, { left: "800px", top: "60px" });
      Object.assign(document.getElementById("welcome").style, { left: "400px", top: "200px" });
    JS
    front = -> { page.evaluate_script("document.elementFromPoint(830, 250).closest('.window').id") }
    assert_equal "window-login.exe", front.call

    # A press on welcome.txt's text, left of login.exe.
    page.driver.browser.action.move_to_location(440, 260).click.perform
    assert_equal "welcome", front.call

    # This press reaches only the login's own document, never the desktop's.
    within_frame(find(".login-frame")) { find("h2", text: "ship your desktop pet").click }
    assert_equal "window-login.exe", front.call
  end

  test "the X closes a window, by mouse or keyboard, until the desktop opens it again" do
    visit root_path
    # login.exe, which a first visit opens, may lie over welcome.txt's X.
    close_login_window
    welcome_box = -> { page.evaluate_script("document.getElementById('welcome').getBoundingClientRect().toJSON()") }
    box = welcome_box.call

    # A press on the X that slides off before release neither drags nor closes.
    page.driver.browser.action.click_and_hold(find("#welcome .windowclose").native).move_by(-150, 80).release.perform
    assert_selector "#welcome"
    assert_equal box, welcome_box.call

    2.times do
      within("#welcome .windowheader") { click_button "close", enable_aria_label: true }
      assert_no_selector "#welcome"
      find(".app", text: "welcome.txt").click
      assert_selector "#welcome"
    end
    assert_equal box, welcome_box.call

    find("#welcome .windowclose").send_keys(:enter)
    assert_no_selector "#welcome"
    find(".app", text: "welcome.txt").click
    find("#welcome .windowclose").send_keys(:space)
    assert_no_selector "#welcome"
    find(".app", text: "welcome.txt").click

    click_link "new to this? check out the guide!"
    within("#window-guide\\.txt .windowheader") { click_button "close", enable_aria_label: true }
    assert_no_selector "#window-guide\\.txt"
    click_link "new to this? check out the guide!"
    within_frame(find("#window-guide\\.txt iframe")) { assert_selector "h1", text: "Build a virtual pet in Godot" }
  end

  test "closing ship.exe keeps its dashboard, and the window behind comes to the front" do
    log_in_as("participant")
    visit root_path(open: "goal")
    within_frame(find(".ship-frame")) { assert_text "your meter" }
    page.execute_script("document.querySelector('.ship-frame').contentWindow.stillHere = true")
    within("#window-goal\\.exe .windowheader") { click_button "close", enable_aria_label: true }
    assert_no_selector "#window-goal\\.exe"

    # welcome.txt comes to the front after ship.exe closes, and both sit at one spot.
    find(".app", text: "welcome.txt").send_keys(:enter)
    find(".app", text: "ship.exe").send_keys(:enter)
    within_frame(find(".ship-frame")) { assert_text "your meter" }
    assert page.evaluate_script("document.querySelector('.ship-frame').contentWindow.stillHere"), "the dashboard did not reload"
    page.execute_script("['window-goal.exe', 'welcome'].forEach((id) => Object.assign(document.getElementById(id).style, { left: '80px', top: '80px' }))")

    front = -> { page.evaluate_script("document.elementFromPoint(300, 130).closest('.window').id") }
    assert_equal "window-goal.exe", front.call
    within("#window-goal\\.exe .windowheader") { click_button "close", enable_aria_label: true }
    assert_equal "welcome", front.call
    find(".app", text: "ship.exe").send_keys(:enter)
    assert_equal "window-goal.exe", front.call
  end

  test "the rock walks in front of the windows and behind the taskbar, and a press on the clear rest of its picture lands behind it" do
    visit root_path
    # What a press lands on, walking or stopped, at the middle of the rock
    # and near the top of its picture, where it draws nothing.
    at_rock = <<~JS
      ((down) => {
        const rock = [...document.querySelectorAll("#desktop-pet, #desktop-pet-static")].find(el => getComputedStyle(el).display !== "none")
        const box = rock.getBoundingClientRect()
        const hit = document.elementFromPoint(box.x + box.width / 2, box.y + box.height * down)
        return hit === rock ? "rock" : hit.closest(".window")?.id || hit.id
      })
    JS
    rock_middle = -> { page.evaluate_script("#{at_rock}(0.55)") }
    rock_top = -> { page.evaluate_script("#{at_rock}(0.1)") }
    assert_equal "rock", rock_middle.call
    # The taskbar alone stays in front of it: a press on the rock's foot,
    # where it stands behind the taskbar's top edge, lands on the taskbar.
    assert_equal "bar", page.evaluate_script("#{at_rock}(0.74)")

    # login.exe, which a visitor's ship.exe opens, over the rock's picture:
    # the rock still shows in front, and the clear top of its picture lets a
    # press through to login.exe.
    find(".app", text: "ship.exe").click
    within_frame(find(".login-frame")) { assert_text "ship your desktop pet" }
    assert_no_selector ".window[data-placing]"
    page.execute_script("Object.assign(document.getElementById('window-login.exe').style, { left: '80px', top: `${innerHeight - 330}px` })")
    assert_equal "rock", rock_middle.call
    assert_equal "window-login.exe", rock_top.call

    # welcome.txt comes to the front and renumbers the windows. The rock stays in front of them all.
    find(".app", text: "welcome.txt").send_keys(:enter)
    page.execute_script("Object.assign(document.getElementById('welcome').style, { left: '80px', top: `${innerHeight - 200}px` })")
    assert_equal "rock", rock_middle.call
    assert_equal "welcome", rock_top.call

    # By keyboard, as welcome.txt may lie over login.exe's X.
    find("#welcome .windowclose").send_keys(:enter)
    find("#window-login\\.exe .windowclose").send_keys(:enter)
    assert_equal "rock", rock_middle.call

    # The icons and the flag stay under the pointer, as before.
    assert page.evaluate_script(<<~JS), "a click on each icon lands on it"
      [...document.querySelectorAll(".app")].every(icon => {
        const box = icon.getBoundingClientRect()
        return icon.contains(document.elementFromPoint(box.x + box.width / 2, box.y + box.height / 2))
      })
    JS
    assert_equal find("#flag-link"), page.evaluate_script("document.elementFromPoint(100, 40)")
  end

  test "a held rock shows above everything, and a dropped one stays in front of the windows" do
    visit root_path
    close_login_window
    welcome_at_own_size
    rock_to 400
    # Wait for the walking GIF, then hold the walk and its stop timers still,
    # so the press below lands on the rock where it was measured.
    box = page.evaluate_async_script(<<~JS)
      const done = arguments[arguments.length - 1]
      const rock = document.getElementById("desktop-pet")
      const hold = () => {
        if (getComputedStyle(rock).display === "none") return setTimeout(hold, 50)
        for (let id = setTimeout(() => {}); id > 0; id--) clearTimeout(id)
        rock.getAnimations().forEach(animation => animation.pause())
        done(rock.getBoundingClientRect().toJSON())
      }
      hold()
    JS
    x, y = box["x"].round, box["y"].round
    top_at = ->(px, py) { page.evaluate_script("(hit => hit.closest('.window')?.id || hit.id)(document.elementFromPoint(#{px}, #{py}))") }

    # welcome.txt lies over the rock's right part and the space above it. The
    # rock shows in front, and the clear edge of its picture lets a press
    # through to the window.
    page.execute_script("Object.assign(document.getElementById('welcome').style, { left: '#{x + 110}px', top: '#{y - 310}px' })")
    assert_equal "desktop-pet", top_at.(x + 40, y + 60)
    assert_equal "desktop-pet", top_at.(x + 120, y + 60)
    assert_equal "welcome", top_at.(x + 135, y + 60)

    # Picked up by the part that shows, the rock stays in sight over the window.
    mouse = page.driver.browser.action
    mouse.move_to_location(x + 40, y + 60).click_and_hold.move_to_location(x + 360, y - 160).perform
    assert_equal "desktop-pet-static", top_at.(x + 360, y - 160)

    # Let go over the window: the rock falls to the floor where it was let
    # go, and stays in front of the window.
    mouse.move_to_location(x + 400, y - 160).release.perform
    assert_no_selector "body.pet-held"
    assert_selector "#desktop-pet[style*='bottom: -9px']"
    landed = page.evaluate_script("parseFloat(document.getElementById('desktop-pet').style.left)")
    assert_in_delta x + 360, landed, 1
    assert_includes %w[desktop-pet desktop-pet-static], top_at.(landed.round + 75, y + 80)
    assert_equal "welcome", top_at.(landed.round + 75, y + 10)
  end

  test "nothing past the right edge slides the desktop sideways" do
    visit root_path
    logo_left = -> { page.evaluate_script("document.querySelector('.background-logo').getBoundingClientRect().left") }
    left = logo_left.call

    # A window half past the right edge, and a Tab or script that reaches its X.
    page.execute_script(<<~JS)
      document.getElementById("welcome").style.left = (innerWidth - 100) + "px"
      document.querySelector("#welcome .windowclose").focus()
      document.querySelector("#welcome .windowclose").scrollIntoView()
    JS
    assert_equal 0, page.evaluate_script("document.body.scrollLeft + document.documentElement.scrollLeft")
    assert_equal left, logo_left.call
    assert page.evaluate_script("document.documentElement.scrollWidth <= innerWidth")
  end

  test "windows open inside a phone-sized browser window, each with its X in reach" do
    resize_browser_to(390, 844) do
      # ship.exe opens by link, which for a visitor is the login in login.exe.
      visit root_path(open: "goal")
      within_frame(find(".login-frame")) { assert_text "ship your desktop pet" }
      assert_inside_browser_window "#welcome"
      assert_inside_browser_window "#window-login\\.exe"
      within("#window-login\\.exe .windowheader") { click_button "close", enable_aria_label: true }
      assert_no_selector "#window-login\\.exe"

      click_link "new to this? check out the guide!"
      assert_inside_browser_window "#window-guide\\.txt"
      %w[#window-guide\\.txt #welcome].each do |window|
        within("#{window} .windowheader") { click_button "close", enable_aria_label: true }
        assert_no_selector window
      end
      assert page.evaluate_script("document.documentElement.scrollWidth <= innerWidth")
    end
  end

  test "a window the browser window shrinks past moves back in, and one that still fits stays put" do
    visit root_path
    assert_selector "#welcome"
    find(".app", text: "ship.exe").click
    within_frame(find(".login-frame")) { assert_text "ship your desktop pet" }
    assert_no_selector ".window[data-placing]"
    # welcome.txt reaches past 1024px, and login.exe, as tall as the login, fits there.
    page.execute_script(<<~JS)
      Object.assign(document.getElementById("welcome").style, { left: "700px", top: "100px" })
      Object.assign(document.getElementById("window-login.exe").style, { left: "100px", top: "100px" })
    JS
    login_box = -> { page.evaluate_script("document.getElementById('window-login.exe').getBoundingClientRect().toJSON()") }
    login = login_box.call

    resize_browser_to(1024, 768) do
      assert_inside_browser_window "#welcome"
      assert_equal login, login_box.call

      # A window closed while the browser window shrinks opens inside it again.
      find("#window-login\\.exe .windowclose").send_keys(:enter)
      assert_no_selector "#window-login\\.exe"
      page.current_window.resize_to(390, 844)
      assert_inside_browser_window "#welcome"
      find(".app", exact_text: "ship.exe").send_keys(:enter)
      assert_inside_browser_window "#window-login\\.exe"
      within("#window-login\\.exe .windowheader") { click_button "close", enable_aria_label: true }
      click_link "new to this? check out the guide!"
      assert_inside_browser_window "#window-guide\\.txt"
    end
  end

  test "a drag on any side or corner of the frame resizes a window, from a floor up to the desktop" do
    visit root_path
    welcome_at_own_size
    # The rock stands in front of the windows, so it waits off to the right,
    # clear of every corner dragged here.
    page.execute_script("['desktop-pet', 'desktop-pet-static'].forEach(id => document.getElementById(id).style.left = '1100px')")
    page.execute_script("Object.assign(document.getElementById('welcome').style, { left: '300px', top: '180px' })")
    assert_equal [ 300, 180, 500, 400 ], window_box("#welcome")
    # Only the cursor shows the frame resizes: its hit areas paint nothing.
    assert page.evaluate_script(<<~JS)
      [...document.querySelectorAll("#welcome .windowresize")].every(area => {
        const style = getComputedStyle(area)
        return style.backgroundImage === "none" && style.backgroundColor === "rgba(0, 0, 0, 0)"
      })
    JS
    # Past the 4px frame, even at a corner, a press lands on the header or the content.
    assert_equal %w[windowheader windowheader windowcontent windowcontent], page.evaluate_script(<<~JS)
      [[310, 190], [790, 190], [310, 570], [790, 570]].map(([x, y]) => document.elementFromPoint(x, y).closest(".windowheader, .windowcontent, .windowresize").className)
    JS

    # Each drag moves its own sides, and the opposite ones stay put. The top
    # stays below the credits throughout.
    {
      n: [ 0, -50, [ 300, 130, 500, 450 ] ], w: [ -50, 0, [ 250, 130, 550, 450 ] ],
      e: [ 50, 0, [ 250, 130, 600, 450 ] ], s: [ 0, 50, [ 250, 130, 600, 500 ] ],
      nw: [ -50, -50, [ 200, 80, 650, 550 ] ], ne: [ 10, -20, [ 200, 60, 660, 570 ] ],
      se: [ 30, 50, [ 200, 60, 690, 620 ] ], sw: [ -30, 30, [ 170, 60, 720, 650 ] ]
    }.each do |edge, (dx, dy, box)|
      resize "#welcome", edge, by: [ dx, dy ]
      assert_equal box, window_box("#welcome"), "a drag on #{edge}"
    end
    # welcome.txt's text can use 720px at most, so a wider drag stops there.
    resize "#welcome", :e, by: [ 100, 0 ]
    assert_equal [ 170, 60, 720, 650 ], window_box("#welcome")
    # The text and the example grid fill the new width.
    assert page.evaluate_script(<<~JS), "the grid spans the window's content"
      (content => content.querySelector(".image-grid").offsetWidth === content.clientWidth - 48)(document.querySelector("#welcome .windowcontent"))
    JS

    # At the floor the whole title and the X fit the header, and the page
    # still scrolls under the wheel.
    resize "#welcome", :se, to: [ 5, 5 ]
    assert_equal [ 170, 60, 200, 80 ], window_box("#welcome")
    assert page.evaluate_script("(title => title.scrollWidth <= title.clientWidth)(document.querySelector('#welcome .headertext'))")
    content = find("#welcome .windowcontent")
    page.driver.browser.action.scroll_from(Selenium::WebDriver::WheelActions::ScrollOrigin.element(content.native), 0, 200).perform
    assert_selector("#welcome .windowcontent") { |scroller| page.evaluate_script("arguments[0].scrollTop", scroller).positive? }

    # Just under the top of the frame the header still drags the window, and
    # a drag, a close, and a reopen keep the size.
    page.driver.browser.action.move_to_location(200, 66).click_and_hold.move_to_location(300, 166).release.perform
    assert_equal [ 270, 160, 200, 80 ], window_box("#welcome")
    within("#welcome .windowheader") { click_button "close", enable_aria_label: true }
    find(".app", text: "welcome.txt").click
    assert_equal [ 270, 160, 200, 80 ], window_box("#welcome")

    # A move past the browser window stops 10px inside it at the sides, at
    # the taskbar's top at the bottom, and at the top where a drag stops too,
    # below the credits.
    width, height = browser_window_size
    top = credits_bottom
    resize "#welcome", :nw, to: [ 0, 0 ]
    assert_equal [ 10, top, 460, 240 - top ], window_box("#welcome")
    # Down to the taskbar, and across to the 720px its text can use.
    resize "#welcome", :se, to: [ width - 1, height - 1 ]
    taskbar = page.evaluate_script("document.getElementById('bar').getBoundingClientRect().top")
    assert_equal [ 10, top, [ width - 20, 720 ].min, taskbar - top ], window_box("#welcome")
    assert_equal "", page.evaluate_script("getSelection().toString()"), "a resize selects no text"
    assert_no_selector "body.dragging"
  end

  test "a resize comes to the front, crosses ship.exe's dashboard, and the dashboard fills the window" do
    visit root_path(open: "goal")
    # A participant's dashboard is long enough to scroll in a short window.
    click_reloading_the_desktop { within_frame(find(".login-frame")) { click_link "participant" } }
    within_frame(find(".ship-frame")) { assert_text "your meter" }
    find(".app", text: "welcome.txt").send_keys(:enter)
    # welcome.txt comes to the front. The two overlap here, with ship.exe
    # whole above the taskbar, and its left edge clear of welcome.txt, where
    # its frame takes a drag.
    page.execute_script(<<~JS)
      const top = Math.min(80, document.getElementById("bar").getBoundingClientRect().top - document.getElementById("window-goal.exe").offsetHeight)
      Object.assign(document.getElementById("window-goal.exe").style, { left: "80px", top: top + "px" })
      Object.assign(document.getElementById("welcome").style, { left: "120px", top: top + "px" })
    JS
    front = -> { page.evaluate_script("document.elementFromPoint(300, 130).closest('.window').id") }
    assert_equal "welcome", front.call

    # A move inward lands on the dashboard before the window shrinks under it.
    # While held, the dashboard ignores the mouse, as in a drag by the header.
    box = window_box("#window-goal\\.exe")
    x, y = on_frame("#window-goal\\.exe", :w)
    mouse = page.driver.browser.action
    mouse.move_to_location(x, y).click_and_hold.move_to_location(x + 200, y).perform
    assert_selector "body.dragging"
    mouse.release.perform
    assert_equal [ box[0] + 200, box[1], box[2] - 200, box[3] ], window_box("#window-goal\\.exe")
    assert_equal "window-goal.exe", front.call
    assert_no_selector "body.dragging"

    # The dashboard keeps its scroll through a resize, and fills the window.
    resize "#window-goal\\.exe", :se, by: [ 0, -400 ]
    page.execute_script("document.querySelector('.ship-frame').contentWindow.scrollTo(0, 100)")
    # The dashboard can use no more than ship.exe opens at, so it grows back to that.
    resize "#window-goal\\.exe", :se, by: [ 500, 50 ]
    assert_equal [ box[0] + 200, box[1], box[2], box[3] - 350 ], window_box("#window-goal\\.exe")
    frame = page.evaluate_script(<<~JS)
      (frame => [frame.offsetWidth, frame.offsetHeight, frame.contentWindow.scrollY])(document.querySelector(".ship-frame"))
    JS
    # All but the 4px frame, the 20px header, and the content's 2px top border.
    assert_equal [ box[2] - 8, box[3] - 350 - 8 - 20 - 2, 100 ], frame
  end

  test "a resized window the browser window shrinks past fits back inside" do
    visit root_path
    find(".app", exact_text: "guide.txt").send_keys(:enter)
    within_frame(find(".guide-frame")) { assert_selector "h1", text: "Build a virtual pet in Godot" }
    assert_no_selector ".window[data-placing]"
    width, height = browser_window_size
    # guide.txt starts where its widest, 720px, reaches the right margin.
    # Each window comes to the front first, so its corner is its own to grab
    # wherever the two opened.
    page.execute_script("Object.assign(document.getElementById('window-guide.txt').style, { left: arguments[0] - 730 + 'px', top: '60px' })", width)
    [ "#welcome", "#window-guide\\.txt" ].each do |window|
      page.execute_script("document.querySelector(arguments[0] + ' .windowclose').focus()", window)
      resize window, :se, to: [ width - 1, height - 1 ]
    end
    left, _, guide_width = window_box("#window-guide\\.txt")
    assert_equal width - 10, left + guide_width

    resize_browser_to(1024, 600) do
      %w[#window-guide\\.txt #welcome].each { |window| assert_inside_browser_window window }
      page.current_window.resize_to(390, 844)
      %w[#window-guide\\.txt #welcome].each { |window| assert_inside_browser_window window }
    end
  end

  test "a finger on the frame resizes a window on a phone" do
    resize_browser_to(390, 844) do
      visit root_path
      close_login_window
      box = window_box("#welcome")
      x, y = on_frame("#welcome", :se)
      finger = Selenium::WebDriver::Interactions.pointer(:touch, name: "finger")
      page.driver.browser.action(devices: [ finger ])
        .move_to_location(x, y).pointer_down(:left).move_to_location(x - 100, y - 150).pointer_up(:left).perform
      assert_equal [ box[0], box[1], box[2] - 100, box[3] - 150 ], window_box("#welcome")
    end
  end

  test "a window flung past any edge or corner keeps enough of its header on the screen to grab" do
    visit root_path
    width, height = browser_window_size
    # The rock stands in front of the windows, so it waits between the spots
    # where the flung window's X ends up.
    page.execute_script("['desktop-pet', 'desktop-pet-static'].forEach(id => document.getElementById(id).style.left = '500px')")
    top = credits_bottom
    # Each fling holds the header by the end that trails, so it pulls the
    # window as far out as it can go: by the X's side going left, by the
    # title going right.
    [ [ 0, 0 ], [ width / 2, 0 ], [ width - 1, 0 ], [ width - 1, height / 2 ],
      [ width - 1, height - 1 ], [ width / 2, height - 1 ], [ 0, height - 1 ], [ 0, height / 2 ] ].each do |to|
      page.execute_script("Object.assign(document.getElementById('welcome').style, { left: '400px', top: '250px' })")
      grab = { 0 => 860, width - 1 => 410 }.fetch(to[0], 650)
      page.driver.browser.action.move_to_location(grab, 262).click_and_hold.move_to_location(*to).release.perform
      header = header_in_reach("#welcome")
      assert_operator header["grab"], :>=, 80, "flung to #{to}"
      assert_operator header["top"], :>=, top, "flung to #{to}"
      assert_operator header["bottom"], :<=, height, "flung to #{to}"
      assert header["close"], "flung to #{to}, the X still takes a press" unless to[0] == width - 1
    end
    assert_no_selector "body.dragging"

    # From the part that shows, a drag brings the window back.
    left, top = window_box("#welcome")
    page.driver.browser.action.move_to_location(20, top + 14).click_and_hold.move_to_location(500, 300).release.perform
    assert_equal [ left + 480, 300 - 14 ], window_box("#welcome")[0, 2]
  end

  test "a header dragged under the credits stays below them, with its X in reach" do
    # At this size the required links show as text in the credits.
    resize_browser_to(1024, 768) do
      visit root_path
      close_login_window
      # The X of welcome.txt would end up over the Security link.
      credit = page.evaluate_script("document.querySelector('#credit-links a[href=\"https://security.hackclub.com\"]').getBoundingClientRect().toJSON()")
      close = page.evaluate_script("document.querySelector('#welcome .windowclose').getBoundingClientRect().toJSON()")
      x, y = (close["x"] - 20).round, (close["y"] + 8).round
      page.driver.browser.action.move_to_location(x, y).click_and_hold
        .move_to_location((credit["x"] + credit["width"] / 2 - 20).round, (credit["y"] + 8).round).release.perform
      header = header_in_reach("#welcome")
      assert_operator credits_bottom, :>, 10
      assert_equal credits_bottom, window_box("#welcome")[1]
      assert header["close"], "the X takes a press"
      within("#welcome .windowheader") { click_button "close", enable_aria_label: true }
      assert_no_selector "#welcome"
    end
  end

  test "a finger drags a window by its header on a phone, and a tap on the X still closes it" do
    resize_browser_to(390, 844) do
      visit root_path
      # On a phone login.exe opens in front of welcome.txt.
      close_login_window
      box = window_box("#welcome")
      finger = Selenium::WebDriver::Interactions.pointer(:touch, name: "finger")
      page.driver.browser.action(devices: [ finger ])
        .move_to_location(100, box[1] + 14).pointer_down(:left).move_to_location(150, box[1] + 214).pointer_up(:left).perform
      assert_equal [ box[0] + 50, box[1] + 200 ], window_box("#welcome")[0, 2]

      # Flung up and off the left, the header stays below the credits, with
      # 80px and its X in sight.
      page.driver.browser.action(devices: [ finger ])
        .move_to_location(300, box[1] + 214).pointer_down(:left).move_to_location(0, 0).pointer_up(:left).perform
      header = header_in_reach("#welcome")
      assert_equal credits_bottom, window_box("#welcome")[1]
      assert_operator header["grab"], :>=, 80
      assert header["close"]

      x, y = page.evaluate_script("(box => [box.x + box.width / 2, box.y + box.height / 2].map(Math.round))(document.querySelector('#welcome .windowclose').getBoundingClientRect())")
      page.driver.browser.action(devices: [ finger ]).move_to_location(x, y).pointer_down(:left).pointer_up(:left).perform
      assert_no_selector "#welcome"
      assert_no_selector "body.dragging"
    end
  end

  test "the rock can be picked up while it stands still, and walks and stops again after a drop" do
    visit root_path
    # welcome.txt stands in the middle, where a drop would land the rock beside it.
    find("#welcome .windowclose").send_keys(:enter)
    # Wait for the rock to stop, then hold its timers still, so it stays
    # stopped for the press. It stops within 6.5 seconds.
    box = using_wait_time(10) do
      page.evaluate_async_script(<<~JS)
        const done = arguments[arguments.length - 1]
        const still = document.getElementById("desktop-pet-static")
        const hold = () => {
          if (getComputedStyle(still).display === "none") return setTimeout(hold, 50)
          for (let id = setTimeout(() => {}); id > 0; id--) clearTimeout(id)
          done(still.getBoundingClientRect().toJSON())
        }
        hold()
      JS
    end
    x, y = (box["x"] + 75).round, (box["y"] + 80).round
    assert_equal "desktop-pet-static", page.evaluate_script("document.elementFromPoint(#{x}, #{y}).id")

    # Short walks and stops from here on, so the test need not wait long.
    page.execute_script("Math.random = () => 0")
    # Up and right, but not onto the trash can, which would take the rock.
    can = page.evaluate_script("document.querySelector('.app[data-key=trash]').getBoundingClientRect().toJSON()")
    up = y - 300
    up = (can["top"] - 20).round if (x + 300).between?(can["left"], can["right"]) && up.between?(can["top"], can["bottom"])
    mouse = page.driver.browser.action
    mouse.move_to_location(x, y).click_and_hold.move_to_location(x + 300, up).perform
    assert_selector "body.pet-held"
    assert_equal "desktop-pet-static", page.evaluate_script("document.elementFromPoint(#{x + 300}, #{up}).id")
    mouse.release.perform

    # It falls back to the floor at its new spot and walks on from there. The
    # spot is where the drop put it. Its walk moves it by a transform, so
    # the spot stays put however long the check takes.
    assert_selector "#desktop-pet[style*='bottom: -9px']"
    assert_in_delta box["x"] + 300, page.evaluate_script("parseFloat(document.getElementById('desktop-pet').style.left)"), 0.01
    walked = page.evaluate_async_script(<<~JS)
      const done = arguments[arguments.length - 1]
      const rock = document.getElementById("desktop-pet")
      const from = rock.getBoundingClientRect().left
      setTimeout(() => done([from, rock.getBoundingClientRect().left].map(Math.round)), 500)
    JS
    assert_operator walked[1], :>, walked[0], "the rock walks"
    assert_selector "#desktop-pet-static", visible: true, wait: 5
    assert_selector "#desktop-pet", visible: true, wait: 5
  end

  # A phone hides the rock, so a tablet carries it.
  test "a finger carries the rock on a touch screen, with no errors" do
    resize_browser_to(768, 1024) do
      visit root_path
      find("#welcome .windowclose").send_keys(:enter)
      rock_to page.evaluate_script("innerWidth / 2 - 75")
      page.execute_script("window.pageErrors = []; addEventListener('error', event => pageErrors.push(event.message))")
      # The rock shows as its GIF or, stopped, its still frame. Either takes
      # the finger. Its timers hold still, so it shows the same until then.
      box = page.evaluate_script(<<~JS)
        (() => {
          for (let id = setTimeout(() => {}); id > 0; id--) clearTimeout(id)
          return [...document.querySelectorAll("#desktop-pet, #desktop-pet-static")].find(el => getComputedStyle(el).display !== "none").getBoundingClientRect().toJSON()
        })()
      JS
      # Where the rock sits as the finger lifts.
      page.execute_script(<<~JS)
        addEventListener("pointerup", () => {
          window.lifted = [document.body.classList.contains("pet-held"), document.getElementById("desktop-pet-static").getBoundingClientRect().top]
        }, { capture: true, once: true })
      JS
      x, y = (box["x"] + 75).round, (box["y"] + 80).round
      # Up and a little right, far above the trash can, which would take the rock.
      across = x + 50
      finger = Selenium::WebDriver::Interactions.pointer(:touch, name: "finger")
      page.driver.browser.action(devices: [ finger ])
        .move_to_location(x, y).pointer_down(:left).move_to_location(across, y - 400).pointer_up(:left).perform
      assert_equal [ true, (box["y"] - 400).round ], page.evaluate_script("[lifted[0], Math.round(lifted[1])]")
      assert_selector "#desktop-pet[style*='bottom: -9px']"
      assert_empty page.evaluate_script("pageErrors")
    end
  end

  test "a rock flung past an edge stays on the screen, one dropped on a window stays there in front of it, and one dropped on the sponsor lands beside it" do
    visit root_path
    # login.exe, as tall as the login, may reach the floor, where the rock lands.
    close_login_window
    welcome_at_own_size
    width, height = browser_window_size
    box = page.evaluate_script(<<~JS)
      (() => {
        for (let id = setTimeout(() => {}); id > 0; id--) clearTimeout(id)
        return [...document.querySelectorAll("#desktop-pet, #desktop-pet-static")].find(el => getComputedStyle(el).display !== "none").getBoundingClientRect().toJSON()
      })()
    JS
    x, y = (box["x"] + 75).round, (box["y"] + 80).round
    held = -> { page.evaluate_script("(box => [box.left, box.top, box.right, box.bottom].map(Math.round))(document.getElementById('desktop-pet-static').getBoundingClientRect())") }
    mouse = page.driver.browser.action
    mouse.move_to_location(x, y).click_and_hold.perform
    [ [ 0, 0 ], [ width - 1, 0 ], [ width - 1, height - 1 ], [ 0, height - 1 ] ].each do |to|
      mouse.move_to_location(*to).perform
      left, top, right, bottom = held.call
      assert_operator left, :>=, 0, "held at #{to}"
      assert_operator top, :>=, 0, "held at #{to}"
      assert_operator right, :<=, width, "held at #{to}"
      assert_operator bottom, :<=, height, "held at #{to}"
    end

    # welcome.txt stands on the floor. Let go over its middle, and the rock
    # lands there, in front of it. The walk after landing moves the rock by a
    # transform, at most 20px either way, and a stopped rock shows its still
    # frame, so either takes a press.
    page.execute_script("Object.assign(document.getElementById('welcome').style, { left: '500px', top: '#{height - 300}px' })")
    mouse.move_to_location(760, height - 400).release.perform
    assert_selector "#desktop-pet[style*='bottom: -9px']"
    rock = page.evaluate_script("parseFloat(document.getElementById('desktop-pet').style.left)")
    assert_in_delta 760 - 75, rock, 1
    assert_includes %w[desktop-pet desktop-pet-static], page.evaluate_script("document.elementFromPoint(#{rock.round + 75}, #{height - 60}).id")

    # Let go over the sponsor's icon, it lands beside it, clear of it with its
    # walk, so the icon always shows.
    sponsor = page.evaluate_script("document.querySelector('.app[data-key=\"armand.sponsor\"]').getBoundingClientRect().toJSON()")
    x, y = rock.round + 75, height - 60
    page.driver.browser.action.move_to_location(x, y).click_and_hold.move_to_location(x - 30, y - 100)
      .move_to_location(sponsor["left"].round + 40, (sponsor["top"] - 100).round).release.perform
    assert_selector "#desktop-pet[style*='bottom: -9px']"
    # What the rock draws spans its middle 68%, and its walk adds 20px each way.
    landed = page.evaluate_script("parseFloat(document.getElementById('desktop-pet').style.left)")
    drawn_left, drawn_right = landed + 150 * 0.16 - 20, landed + 150 * 0.84 + 20
    assert drawn_left >= sponsor["right"] - 1 || drawn_right <= sponsor["left"] + 1, "the rock lands clear of the sponsor's icon"
  end

  test "nothing on the desktop takes a text selection, and text in a window still does" do
    visit root_path
    selected = -> { page.evaluate_script("getSelection().toString()") }
    assert_desktop_unselected = lambda do
      [ "get cool merch", "Terms & Privacy", "gulp", "welcome.txt", "guide.txt", "ship.exe" ].each do |text|
        assert_not_includes selected.call, text
      end
    end
    center = ->(selector) { page.evaluate_script("(box => [box.x + box.width / 2, box.y + box.height / 2].map(Math.round))(document.querySelector(arguments[0]).getBoundingClientRect())", selector) }
    # The two ends of "make a desktop pet" at the start of welcome.txt.
    from, to = page.evaluate_script(<<~JS)
      (() => {
        const node = document.querySelector("#welcome .windowcontent p").firstChild
        const range = document.createRange()
        range.setStart(node, node.textContent.indexOf("make"))
        range.setEnd(node, node.textContent.indexOf(", ship"))
        const box = range.getBoundingClientRect()
        const y = Math.round(box.top + box.height / 2)
        return [[Math.round(box.left + 2), y], [Math.round(box.right - 2), y]]
      })()
    JS
    mouse = page.driver.browser.action

    # Cmd+A runs this command. It picks up the window's text and nothing else.
    page.execute_script("document.execCommand('selectAll')")
    assert_includes selected.call, "make a desktop pet, ship it (put it out where others can use it)"
    assert_desktop_unselected.call

    # A drag from the wallpaper, over the line under the logo and an icon, into the window.
    page.execute_script("getSelection().removeAllRanges()")
    mouse.move_to_location(1200, 600).click_and_hold.move_to_location(*center.(".background-logo-text"))
      .move_to_location(*center.(".app:nth-child(2) p")).move_to_location(*to).release.perform
    assert_equal "", selected.call

    # A drag across the window's text selects it, and on out onto the
    # wallpaper it keeps to the window.
    mouse.move_to_location(*from).click_and_hold.move_to_location(*to).perform
    assert_includes selected.call, "a desktop pe"
    mouse.move_to_location(300, 600).release.perform
    assert_desktop_unselected.call

    # Double-clicks on the desktop select no word.
    page.execute_script("getSelection().removeAllRanges()")
    [ ".background-logo-text", ".background-logo", "#bar p:first-child", "#welcome .headertext", ".app:nth-child(2) p" ].each do |selector|
      find(selector).double_click
    end
    assert_selector "#window-guide\\.txt"
    assert_equal "", selected.call

    # The icons and the flag never drag out of the desktop as pictures.
    assert page.evaluate_script("[...document.querySelectorAll('.appicon, a.app, #flag-link')].every(element => !element.draggable)")

    # The login in login.exe is a page of its own, and its text still selects.
    # Enter opens it, as the guide.txt a double-click opened may lie over it.
    find(".app", text: "ship.exe").send_keys(:enter)
    within_frame(find(".login-frame")) do
      assert_text "ship your desktop pet"
      page.execute_script("document.execCommand('selectAll')")
      assert_includes selected.call, "ship your desktop pet"
    end
  end

  private
    # The four required links show as text under the sponsor, on one line,
    # and a tap on each lands on it.
    def assert_credit_links(where)
      within "#credit-links" do
        REQUIRED_LINKS.each do |label, url|
          assert_equal URI(url).normalize.to_s, find_link(label, exact_text: true)[:href], "#{label} #{where}"
        end
      end
      tops, reachable = page.evaluate_script(<<~JS)
        (links => [
          [...new Set(links.map(link => Math.round(link.getBoundingClientRect().top)))],
          links.every(link => {
            const box = link.getBoundingClientRect()
            return document.elementFromPoint(box.x + box.width / 2, box.y + box.height / 2) === link
          })
        ])([...document.querySelectorAll("#credit-links a")].filter(link => link.offsetParent))
      JS
      # With the sponsor's credit, a phone's row takes two lines.
      assert_operator tops.size, :<=, 2, "the links fit two lines #{where}"
      assert reachable, "a tap on each link lands on it #{where}"
    end

    def browser_window_size
      page.evaluate_script("[document.documentElement.clientWidth, document.documentElement.clientHeight]")
    end

    # The desktop starts below the credits: no window goes above them.
    def credits_bottom
      page.evaluate_script("Math.round(document.getElementById('credits').getBoundingClientRect().bottom)")
    end

    # How much of a window's header takes a press: the width, along its
    # middle, where a press lands on the header and not on its X, its top
    # and bottom, and whether a press on the X lands on it.
    def header_in_reach(window)
      page.evaluate_script(<<~JS, find(window))
        (window => {
          const header = window.querySelector(".windowheader"), close = window.querySelector(".windowclose")
          const box = header.getBoundingClientRect(), x = close.getBoundingClientRect()
          let grab = 0
          for (let left = 0; left < document.documentElement.clientWidth; left++) {
            const hit = document.elementFromPoint(left, box.top + box.height / 2)
            if (header.contains(hit) && !close.contains(hit)) grab++
          }
          const onClose = document.elementFromPoint(x.left + x.width / 2, x.top + x.height / 2)
          return { grab, top: Math.round(box.top), bottom: Math.round(box.bottom), close: close.contains(onClose) }
        })(arguments[0])
      JS
    end

    def window_box(selector)
      page.evaluate_script("(box => [box.left, box.top, box.width, box.height].map(Math.round))(document.querySelector(arguments[0]).getBoundingClientRect())", selector)
    end

    # The rock on the floor between the bottom groups, clear of the icons at
    # its start at the bottom left, as a drop there would leave it.
    def rock_to(left)
      page.execute_script("document.getElementById('desktop-pet').style.left = arguments[0] + 'px'", left)
    end

    # A point on a window's 4px frame, by compass point: :n is the top side,
    # :e the right, and :se the bottom-right corner.
    def on_frame(window, edge)
      left, top, width, height = window_box(window)
      x = { "w" => left + 2, "e" => left + width - 2 }.fetch(edge.to_s[/[ew]/], left + width / 2)
      y = { "n" => top + 2, "s" => top + height - 2 }.fetch(edge.to_s[/[ns]/], top + height / 2)
      [ x, y ]
    end

    # Drags a side or corner of the frame by an offset, or to a point in the
    # browser window.
    def resize(window, edge, by: nil, to: nil)
      x, y = on_frame(window, edge)
      to ||= [ x + by[0], y + by[1] ]
      page.driver.browser.action.move_to_location(x, y).click_and_hold.move_to_location(*to).release.perform
    end

    # Rails sizes the browser once for every test, so a test that resizes it
    # puts the old size back.
    def resize_browser_to(width, height)
      size = page.current_window.size
      page.current_window.resize_to(width, height)
      yield
    ensure
      page.current_window.resize_to(*size)
    end

    # Waits until the window's whole box lies inside the browser window. A
    # resize moves windows on the browser's next event, not at once.
    def assert_inside_browser_window(selector)
      assert_selector selector do |window|
        page.evaluate_script(<<~JS, window)
          (window => {
            const box = window.getBoundingClientRect(), root = document.documentElement
            return box.left >= 0 && box.top >= 0 && box.right <= root.clientWidth && box.bottom <= root.clientHeight
          })(arguments[0])
        JS
      end
    end
end
