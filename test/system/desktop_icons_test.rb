require "application_system_test_case"

# The desktop icons in a real browser: they sit on a grid from the top left,
# a click opens and selects one, a drag moves the selected icons to free
# cells, a drag on the wallpaper selects, and the layout lasts in the browser.
class DesktopIconsTest < ApplicationSystemTestCase
  # The layout depends on the size of the page, so each test sets the page,
  # not the browser window around it, to 1440x900.
  setup do
    @window_size = page.current_window.size
    resize_viewport_to(1440, 900)
  end

  teardown do
    page.driver.browser.execute_cdp("Emulation.clearDeviceMetricsOverride")
    page.current_window.resize_to(*@window_size)
  end

  test "every icon starts on the grid, clear of the flag, welcome.txt, and each other" do
    [ [ 1440, 900 ], [ 1024, 768 ], [ 390, 844 ] ].each do |width, height|
      resize_viewport_to(width, height) do
        forget_open_windows
        visit root_path
        # On a phone welcome.txt and login.exe open over most of the desktop, so
        # close them first. On a desktop they leave every icon in reach.
        if width < 500
          close_login_window
          within("#welcome .windowheader") { click_button "close", enable_aria_label: true }
        end
        wait_for_rock
        cells = icon_cells
        # On a phone the text row stands in for the five icons that link off the site.
        assert_equal width < 561 ? 5 : 10, cells.size, "at #{width}x#{height}"
        assert_equal cells.size, cells.values.uniq.size, "no two icons share a cell at #{width}x#{height}"
        assert cells.values.flatten.all?(Integer), "each icon sits on a cell at #{width}x#{height}"
        # Down each column from the top left, below the flag. On a phone,
        # along the first row below the logo's line.
        assert_equal [ 0, width < 561 ? cells.values.map(&:last).min : 1 ], cells["welcome.txt"], "at #{width}x#{height}"
        assert_empty unreachable_icons, "at #{width}x#{height}"
        assert page.evaluate_script(<<~JS), "every icon lies inside the screen, above the taskbar, at #{width}x#{height}"
          [...document.querySelectorAll(".app")].every(icon => {
            const box = icon.getBoundingClientRect()
            return box.left >= 0 && box.right <= innerWidth && box.top >= 0 && box.bottom <= document.getElementById("bar").getBoundingClientRect().top
          })
        JS
      end
    end
  end

  test "the grid fills the desktop edge to edge, so a drop at the far right or the bottom lands in the last column or row" do
    [ [ 1440, 900 ], [ 1024, 768 ], [ 390, 844 ] ].each do |width, height|
      resize_viewport_to(width, height) do
        forget_open_windows
        visit root_path
        close_login_window
        within("#welcome .windowheader") { click_button "close", enable_aria_label: true }
        cols, rows = grid
        cell_width, cell_height = cell
        bar = page.evaluate_script("document.getElementById('bar').getBoundingClientRect().top")
        # Whole columns and rows divide the desktop, each at least an icon.
        assert_in_delta width, cols * cell_width, 1, "at #{width}x#{height}"
        assert_in_delta bar, rows * cell_height, 1, "at #{width}x#{height}"
        # A phone's icons are 168px wide, a desktop's 102px, with room for two lines of label.
        assert_operator cell_width, :>=, width < 561 ? 168 : 102
        assert_operator cell_height, :>=, width < 561 ? 120 : 140

        # In the bottom right corner: the last column, which meets the right
        # edge, and the last row, just above the taskbar. On a desktop the
        # trash starts there, so it moves aside first.
        drag icon("trash"), to: [ width / 2, height / 2 ] if width >= 561
        drag icon("guide.txt"), to: [ width - 1, height - 1 ]
        assert_equal [ cols - 1, rows - 1 ], icon_cells["guide.txt"], "at #{width}x#{height}"
        box = icon_box("guide.txt")
        assert_in_delta width - cell_width / 2, box["x"] + box["width"] / 2, 1, "centred in the last column at #{width}x#{height}"
        assert_operator box["bottom"], :<=, bar
        # On a desktop a one-line label, as guide.txt's, leaves its second line's 20px free.
        box_height, free = width < 561 ? [ 120, 0 ] : [ 140, 20 ]
        assert_operator bar - box["bottom"], :<=, (cell_height - box_height) / 2 + free + 1, "just above the taskbar at #{width}x#{height}"

        # At the far right halfway down, where that column is free.
        next if width < 500
        drag icon("ship.exe"), to: [ width - 1, height / 2 ]
        assert_equal cols - 1, icon_cells["ship.exe"][0], "at #{width}x#{height}"
      end
    end

    # Resized small and back, every icon stays on the screen above the taskbar,
    # once the page has taken its new size.
    [ [ 390, 844 ], [ 1440, 900 ] ].each do |width, height|
      resize_viewport_to(width, height)
      page.document.synchronize do
        inside = page.evaluate_script(<<~JS)
          (bar => [...document.querySelectorAll(".app")].every(icon => {
            const box = icon.getBoundingClientRect()
            return box.left >= 0 && box.right <= innerWidth && box.top >= 0 && box.bottom <= bar
          }))(document.getElementById("bar").getBoundingClientRect().top)
        JS
        raise Capybara::ExpectationNotMet, "an icon lies off the screen at #{width}x#{height}" unless inside
      end
    end
  end

  test "a phone hides the rock, which leaves the floor to the icons, and a desktop keeps it" do
    resize_viewport_to(390, 844) do
      visit root_path
      assert_no_selector "#desktop-pet, #desktop-pet-static"
      # With no rock on the floor, the grid's bottom row is as clear as the rest.
      close_login_window
      within("#welcome .windowheader") { click_button "close", enable_aria_label: true }
      cols, rows = grid
      drag icon("guide.txt"), to: [ 389, 843 ]
      assert_equal [ cols - 1, rows - 1 ], icon_cells["guide.txt"]
      assert_empty unreachable_icons
    end
    visit root_path
    # Walking or stopped, as its GIF or its still frame.
    assert_selector "#desktop-pet, #desktop-pet-static", visible: true
  end

  test "a click opens an icon and selects it, a click on the wallpaper clears it, and a modifier click selects without opening" do
    visit root_path
    icon("guide.txt").click
    within_frame(find("#window-guide\\.txt iframe")) { assert_selector "h1", text: "Build a virtual pet in Godot" }
    assert_equal [ "guide.txt" ], selected

    # A click on another icon selects that one alone. A visitor's ship.exe
    # opens the login.
    icon("ship.exe").click
    assert_selector "#window-login\\.exe"
    assert_equal [ "ship.exe" ], selected

    click_wallpaper
    assert_empty selected
    %w[#window-login\\.exe #window-guide\\.txt].each do |window|
      within("#{window} .windowheader") { click_button "close", enable_aria_label: true }
    end

    # Shift or Cmd adds an icon to the selection or takes it out, and opens
    # nothing, a link included. (Ctrl does too, but on a Mac a Ctrl-click is
    # a right-click.)
    icon("ship.exe").click(:shift)
    icon("Hack Club").click(:meta)
    icon("Terms & Privacy").click(:shift)
    assert_equal [ "ship.exe", "Hack Club", "Terms & Privacy" ], selected
    icon("Hack Club").click(:meta)
    assert_equal [ "ship.exe", "Terms & Privacy" ], selected
    assert_no_selector "#window-login\\.exe"
    assert_equal 1, windows.size
  end

  test "a double-click opens a window once" do
    visit root_path
    icon("guide.txt").double_click
    assert_selector "#window-guide\\.txt", count: 1
    icon("ship.exe").double_click
    within_frame(find(".login-frame")) { assert_text "ship your desktop pet" }
    assert_selector ".window", count: 3
    assert_selector ".login-frame", count: 1
  end

  test "a drag moves an icon to the free cell under it, opens nothing, and never lands on another icon" do
    visit root_path
    # welcome.txt would cover the bottom right corner, where the last drag goes.
    close_login_window
    within("#welcome .windowheader") { click_button "close", enable_aria_label: true }
    page.execute_script("window.pageErrors = []; addEventListener('error', event => pageErrors.push(event.message))")
    start = icon_cells

    # Three cells right and a little off: it snaps to the cell under it.
    drag icon("guide.txt"), by: [ cell[0] * 3 + 20, -30 ]
    assert_equal [ start["guide.txt"][0] + 3, start["guide.txt"][1] ], icon_cells["guide.txt"]
    assert_no_selector "#window-guide\\.txt"
    assert_equal [ "guide.txt" ], selected

    # Dropped on ship.exe, it takes the free cell nearest, and ship.exe stays.
    drag icon("guide.txt"), to: icon_center("ship.exe")
    cells = icon_cells
    assert_equal start["ship.exe"], cells["ship.exe"]
    assert_equal cells.size, cells.values.uniq.size
    assert_operator distance(cells["guide.txt"], cells["ship.exe"]), :<=, 1.5

    # Flung past the bottom right corner, it stays on the screen above the
    # taskbar, in the last column, above the trash, which holds the corner.
    width, height = browser_window_size
    drag icon("guide.txt"), to: [ width - 1, height - 1 ]
    assert_equal grid.map { it - 1 }, icon_cells["trash"]
    assert_equal [ grid.first - 1, grid.last - 2 ], icon_cells["guide.txt"]
    assert_empty unreachable_icons
    assert_no_selector "body.dragging"
    assert_empty page.evaluate_script("pageErrors")
  end

  test "a drag across the wallpaper takes an icon only where its picture is drawn, and a click still takes all of it" do
    [ 1, 2 ].each do |scale|
      resize_viewport_to(1440, 900, scale:) do
        forget_open_windows
        visit root_path
        close_login_window
        within("#welcome .windowheader") { click_button "close", enable_aria_label: true }
        # guide.txt's page is drawn from 17.5% in and 10% down its picture.
        # welcome.txt sits left of it in the row, so the bands start between the two.
        picture = box_of("guide.txt", ".appicon")
        left, top = picture["left"].round, picture["top"].round
        start = box_of("welcome.txt")["right"].round + 2

        band [ start, top - 8 ], [ left + 6, top + 4 ]
        assert_empty selected, "a band over the picture's clear corner, at #{scale}x"
        band [ start, top - 8 ], [ left + 16, top + 10 ]
        assert_equal [ "guide.txt" ], selected, "a band into what the picture draws, at #{scale}x"

        # The label does not count.
        label = box_of("guide.txt", "p")
        band [ box_of("guide.txt")["right"].round + 12, label["top"].round + 8 ], [ (label["left"] + label["width"] / 2).round, label["bottom"].round - 2 ]
        assert_empty selected, "a band over the label alone, at #{scale}x"

        # A click on the clear corner still opens the icon, as before.
        page.driver.browser.action.move_to_location(left + 3, top + 3).click.perform
        assert_selector "#window-guide\\.txt"
        assert_equal [ "guide.txt" ], selected
      end
    end
  end

  test "a drag across the wallpaper selects every icon it touches, and never starts on a window" do
    visit root_path
    icon("armand.sponsor").click
    # From the wallpaper right of the bottom left group, back over Security's
    # picture and the right edge of Fulfillment's beside it, and no
    # further. What counts is each picture, not its label.
    fulfillment = box_of("Fulfillment", ".appicon")
    security = box_of("Security", ".appicon")
    from = [ (icon_box("Security")["right"] + 30).round, (security["top"] + 5).round ]
    to = [ (fulfillment["right"] - 4).round, (security["bottom"] - 5).round ]
    mouse = page.driver.browser.action
    mouse.move_to_location(*from).click_and_hold.move_to_location(from[0] - 20, from[1] + 10).move_to_location(*to).perform
    assert_selector "#selection-box", visible: true
    assert_equal [ "Fulfillment", "Security" ], selected
    mouse.release.perform
    assert_no_selector "#selection-box", visible: true
    assert_equal [ "Fulfillment", "Security" ], selected

    # A drag that starts on a window moves no box and keeps the selection.
    content = page.evaluate_script("(box => [box.x + 40, box.y + 40].map(Math.round))(document.querySelector('#welcome .windowcontent').getBoundingClientRect())")
    mouse.move_to_location(*content).click_and_hold.move_to_location(100, 200).release.perform
    assert_equal [ "Fulfillment", "Security" ], selected
  end

  test "the box is drawn twice in marker, and the two drawings take turns until the drag ends" do
    visit root_path
    close_login_window
    mouse = page.driver.browser.action
    # On the wallpaper right of welcome.txt, where login.exe was.
    mouse.move_to_location(1100, 420).click_and_hold.move_to_location(1120, 440).move_to_location(1300, 570).perform
    drawings = page.evaluate_script(<<~JS)
      [...document.querySelectorAll("#selection-box path")].map(path => path.getAttribute("d"))
    JS
    # Two outlines of the four sides, each side a filled stroke of its own,
    # alike but not the same.
    assert_equal 2, drawings.size
    drawings.each { |d| assert_equal 4, d.scan("M").size }
    assert_not_equal(*drawings)
    assert_equal "none", page.evaluate_script("getComputedStyle(document.getElementById('selection-box')).borderStyle")
    # Over most of a second, each drawing shows in turn, one at a time.
    shown = shown_drawings
    assert_equal [ 0, 1 ], shown.flatten.uniq.sort
    assert shown.all? { |visible| visible.size == 1 }, "one drawing shows at a time"
    assert_operator shown.each_cons(2).count { |a, b| a != b }, :>=, 2

    # Grown, the side along the top, which starts at the press, keeps the
    # line it had drawn.
    top_side = -> { page.evaluate_script("document.querySelector('#selection-box path').getAttribute('d').split('M')[1].split('L').slice(0, 40).join('L')") }
    before = top_side.call
    mouse.move_to_location(1350, 750).perform
    assert_equal before, top_side.call

    # Small and large, dragged every way, the four sides meet at each corner
    # in both drawings: none runs more than a pixel past the outer edge of
    # the side it meets, and each reaches into it, so no corner gapes.
    [ [ 1, 1 ], [ -1, 1 ], [ 1, -1 ], [ -1, -1 ] ].product([ 14, 60, 320 ]).each do |(sx, sy), size|
      mouse.move_to_location(1100 + sx * size, 420 + sy * (size * 0.7).round).perform
      corner_fits.each do |past, into|
        assert_operator past, :<=, 1, "a side runs past a corner, dragged #{[ sx, sy ]} by #{size}"
        assert_operator into, :<=, 0, "a corner gapes, dragged #{[ sx, sy ]} by #{size}"
      end
    end

    mouse.release.perform
    assert_no_selector "#selection-box", visible: true
  end

  test "a selected icon shows as on XP, a blue fill behind its label and a tint on its picture, and every label is outlined" do
    visit root_path
    icon("guide.txt").click
    looks = page.evaluate_script(<<~JS)
      Object.fromEntries([...document.querySelectorAll(".app")].map(icon => {
        const label = icon.querySelector("p"), style = getComputedStyle(label)
        const text = document.createRange()
        text.selectNodeContents(label)
        return [icon.textContent.trim(), {
          box: getComputedStyle(icon).backgroundColor, fill: style.backgroundColor, color: style.color,
          tint: getComputedStyle(icon.querySelector(".appicon")).filter, outline: style.webkitTextStrokeWidth,
          shadow: style.textShadow, hugs: Math.abs(label.getBoundingClientRect().width - text.getBoundingClientRect().width - 2) < 1
        }]
      }))
    JS
    selected, plain = looks.values_at("guide.txt", "ship.exe")
    assert_equal [ "rgba(0, 0, 0, 0)", "rgb(58, 112, 184)", "rgb(255, 255, 255)" ], selected.values_at("box", "fill", "color")
    assert_includes selected["tint"], "#icon-tint"
    assert selected["hugs"], "the fill hugs the label, 1px past its text each side"
    assert_equal [ "rgba(0, 0, 0, 0)", "rgba(0, 0, 0, 0)", "none" ], plain.values_at("box", "fill", "tint")
    # White text, a thin dark outline, and a soft shadow down and right, selected or not.
    looks.each_value do |look|
      assert_equal [ "rgb(255, 255, 255)", "0.4px", "rgba(0, 0, 0, 0.6) 1px 1px 2px" ], look.values_at("color", "outline", "shadow")
    end
    # The tint lies only where the picture is drawn.
    assert_selector "#icon-tint feComposite[operator=in][in2=SourceAlpha]", visible: :all
  end

  test "an icon that leaves the site wears a shortcut arrow on its picture's corner, and the others do not" do
    visit root_path
    arrows = page.evaluate_script(<<~JS)
      [...document.querySelectorAll(".app")].map(icon => [icon.textContent.trim(), !!icon.querySelector(".shortcut")])
    JS
    assert_equal [ "Hack Club", "Terms & Privacy", "Fulfillment", "Security", "armand.sponsor" ], arrows.select(&:last).map(&:first)
    assert_equal [ "welcome.txt", "guide.txt", "ship.exe", "requirements.txt", "trash" ], arrows.reject(&:last).map(&:first)

    # A third of the picture, flush with its bottom left corner, and a press
    # there lands on the icon.
    placed = page.evaluate_script(<<~JS)
      [...document.querySelectorAll(".app .shortcut")].map(arrow => {
        const icon = arrow.closest(".app"), picture = icon.querySelector(".appicon").getBoundingClientRect(), box = arrow.getBoundingClientRect()
        const hit = document.elementFromPoint(box.x + 4, box.bottom - 4)
        return [box.x - picture.x, box.bottom - picture.bottom, box.width, icon.contains(hit) && hit !== arrow]
      })
    JS
    assert_equal [ [ 0, 0, 22, true ] ], placed.uniq

    # It takes the selection's tint with its icon.
    icon("Security").click(:shift)
    assert_includes page.evaluate_script("getComputedStyle(document.querySelector('.app.selected .shortcut')).filter"), "#icon-tint"
  end

  test "with reduced motion, the box keeps one drawing" do
    page.driver.browser.execute_cdp("Emulation.setEmulatedMedia", features: [ { name: "prefers-reduced-motion", value: "reduce" } ])
    visit root_path
    page.driver.browser.action.move_to_location(500, 500).click_and_hold.move_to_location(520, 520).move_to_location(700, 650).perform
    assert_equal [ [ 0 ] ], shown_drawings.uniq
    page.driver.browser.action.release.perform
    assert_no_selector "#selection-box", visible: true
  ensure
    page.driver.browser.execute_cdp("Emulation.setEmulatedMedia", features: [])
  end

  test "a selected group moves together, and each icon snaps to a free cell" do
    visit root_path
    icon("welcome.txt").click
    icon("guide.txt").click(:shift)
    icon("ship.exe").click(:shift)
    # Most of a column right, along their row: each takes the free cell
    # nearest where it fell, a column on.
    start = icon_cells
    drag icon("guide.txt"), by: [ (cell[0] * 1.4).round, 0 ]
    cells = icon_cells
    assert_equal cells.size, cells.values.uniq.size, "no two icons share a cell"
    %w[Hack\ Club Fulfillment Security armand.sponsor].each { |label| assert_equal start[label], cells[label], "#{label} stays put" }
    %w[welcome.txt guide.txt ship.exe].each { |label| assert_equal [ start[label][0] + 1, start[label][1] ], cells[label], "#{label} moved right" }
    assert_equal %w[welcome.txt guide.txt ship.exe], selected

    # Flung up and left past the corner, the group stays whole and on the screen.
    drag icon("guide.txt"), to: [ 0, 0 ]
    cells = icon_cells
    assert_equal cells.size, cells.values.uniq.size
    assert cells.values.flatten.none?(&:negative?)
  end

  test "the layout lasts through a reload, and a resize moves only the icons that no longer fit" do
    visit root_path
    # welcome.txt would cover the cell guide.txt takes at the smaller size.
    close_login_window
    within("#welcome .windowheader") { click_button "close", enable_aria_label: true }
    start = icon_cells
    cols, rows = grid
    # guide.txt to the last column, above the trash in the corner, and
    # Fulfillment two cells up.
    drag icon("guide.txt"), by: [ cell[0] * (cols - 1 - start["guide.txt"][0]), cell[1] * (rows - 2 - start["guide.txt"][1]) ]
    drag icon("Fulfillment"), by: [ 0, -cell[1] * 2 ]
    moved = icon_cells
    assert_equal [ cols - 1, rows - 2 ], moved["guide.txt"]
    assert_equal [ start["Fulfillment"][0], start["Fulfillment"][1] - 2 ], moved["Fulfillment"]

    visit root_path
    assert_equal moved, icon_cells
    # The reload keeps welcome.txt closed. login.exe opens again, and would
    # lie over the last column at the smaller size, so it closes.
    assert_no_selector "#welcome"
    close_login_window

    resize_viewport_to(1024, 768) do
      # guide.txt's column is off the screen now, and so are the bottom right
      # group's, and the bottom row, so each takes the free cell nearest it.
      # The others stay put.
      assert_selector(".app", exact_text: "guide.txt") { |icon| cell_of(icon) != moved["guide.txt"] }
      cells = icon_cells
      fits = moved.select { |_, (col, row)| col < grid.first && row < grid.last }
      assert_includes moved.keys - fits.keys, "guide.txt"
      assert_equal fits, cells.slice(*fits.keys)
      (moved.keys - fits.keys).each { |label| assert_operator cells[label][0], :<, grid.first, "#{label} moves onto the grid" }
      assert_equal cells.size, cells.values.uniq.size
      assert_empty unreachable_icons

      # Back at the old size, guide.txt goes back to its cell.
      resize_viewport_to(1440, 900)
      assert_selector(".app", exact_text: "guide.txt") { |icon| cell_of(icon) == moved["guide.txt"] }
      assert_equal moved, icon_cells

      # A visit at a size the saved layout does not fit starts from the top
      # left again, and forgets it.
      resize_viewport_to(1024, 768)
      visit root_path
      assert_equal start["guide.txt"], icon_cells["guide.txt"]
      assert_nil page.evaluate_script("localStorage.getItem('playground-desktop-icons')")
    end
  end

  test "a new icon takes a free cell and moves none of the saved ones" do
    visit root_path
    drag icon("ship.exe"), by: [ cell[0] * 4, 0 ]
    saved = icon_cells
    # Forget where armand.sponsor was, as for an icon the desktop just gained.
    page.execute_script(<<~JS)
      const icons = JSON.parse(localStorage.getItem("playground-desktop-icons"))
      delete icons["armand.sponsor"]
      localStorage.setItem("playground-desktop-icons", JSON.stringify(icons))
    JS
    visit root_path
    cells = icon_cells
    assert_equal saved.except("armand.sponsor"), cells.except("armand.sponsor")
    # The sponsor's icon takes its own cell in the bottom left group again.
    assert_equal [ 0, grid.last - 1 ], cells["armand.sponsor"]
  end

  test "a tap opens an icon on a phone, and a finger drag moves it" do
    resize_viewport_to(390, 844) do
      visit root_path
      page.execute_script("window.pageErrors = []; addEventListener('error', event => pageErrors.push(event.message))")
      close_login_window
      within("#welcome .windowheader") { click_button "close", enable_aria_label: true }
      finger = Selenium::WebDriver::Interactions.pointer(:touch, name: "finger")

      # A tap that wobbles a few pixels still opens.
      x, y = icon_center("guide.txt")
      page.driver.browser.action(devices: [ finger ])
        .move_to_location(x, y).pointer_down(:left).move_to_location(x + 3, y + 2).pointer_up(:left).perform
      assert_selector "#window-guide\\.txt"
      assert_equal [ "guide.txt" ], selected
      within("#window-guide\\.txt .windowheader") { click_button "close", enable_aria_label: true }

      # A long drag moves it, and opens nothing.
      x, y = icon_center("ship.exe")
      col, row = icon_cells["ship.exe"]
      page.driver.browser.action(devices: [ finger ])
        .move_to_location(x, y).pointer_down(:left).move_to_location(x + 40, y + 60)
        .move_to_location((x + cell[0]).round, (y + cell[1] * 2).round).pointer_up(:left).perform
      assert_equal [ col + 1, row + 2 ], icon_cells["ship.exe"]
      assert_no_selector "#window-goal\\.exe"
      assert_equal 0, page.evaluate_script("document.scrollingElement.scrollTop")
      assert_empty page.evaluate_script("pageErrors")
    end
  end

  test "the arrow keys move the selection between icons, and Enter opens one" do
    visit root_path
    page.execute_script("document.querySelector('.app').focus()")
    [ [ :down, "requirements.txt" ], [ :down, "armand.sponsor" ], [ :right, "Fulfillment" ], [ :up, "guide.txt" ], [ :left, "welcome.txt" ] ].each do |key, label|
      page.driver.browser.switch_to.active_element.send_keys(key)
      assert_equal [ label ], selected
      assert_equal label, page.evaluate_script("document.activeElement.textContent.trim()")
    end
    page.driver.browser.switch_to.active_element.send_keys(:right)
    page.driver.browser.switch_to.active_element.send_keys(:enter)
    assert_selector "#window-guide\\.txt"
  end

  private
    def icon(label)
      find(".app", exact_text: label)
    end

    # Each showing icon's cell, as [column, row], by its label. On a phone the
    # icons that link off the site do not show.
    def icon_cells
      page.evaluate_script(<<~JS).to_h
        [...document.querySelectorAll(".app")].filter(icon => icon.offsetParent).map(icon => [icon.textContent.trim(), icon.dataset.cell.split(",").map(Number)])
      JS
    end

    # The grid's columns and rows.
    def grid
      find("#apps", visible: :all)["data-grid"].split.map(&:to_i)
    end

    # A cell's width and height: the grid divides the desktop, the browser
    # window above the taskbar, exactly.
    def cell
      cols, rows = grid
      width, bar = page.evaluate_script("[document.documentElement.clientWidth, document.getElementById('bar').getBoundingClientRect().top]")
      [ width.to_f / cols, bar.to_f / rows ]
    end

    def cell_of(icon)
      icon_cells[icon.text]
    end

    def selected
      page.evaluate_script("[...document.querySelectorAll('.app.selected')].map(icon => icon.textContent.trim())")
    end

    # A part of an icon, by CSS selector, or the whole icon.
    def box_of(label, part = nil)
      page.evaluate_script("(icon => (arguments[1] ? icon.querySelector(arguments[1]) : icon).getBoundingClientRect().toJSON())(arguments[0])", icon(label), part)
    end

    # Draws a selection box from one point to another, and lets go.
    def band(from, to)
      page.driver.browser.action.move_to_location(*from).click_and_hold
        .move_to_location(from[0] + 6, from[1] + 6).move_to_location(*to).release.perform
      assert_no_selector "#selection-box", visible: true
    end

    def icon_box(label)
      page.evaluate_script("arguments[0].getBoundingClientRect().toJSON()", icon(label))
    end

    def icon_center(label)
      box = icon_box(label)
      [ (box["x"] + box["width"] / 2).round, (box["y"] + box["height"] / 2).round ]
    end

    # Icons whose picture or label a press would miss: under a window or the
    # credits, or off the screen. The rock walks in front of the icons, and
    # on, so a press it takes does not count.
    def unreachable_icons
      page.evaluate_script(<<~JS)
        [...document.querySelectorAll(".app")].filter(icon => icon.offsetParent).filter(icon => [".appicon", "p"].some(part => {
          const box = icon.querySelector(part).getBoundingClientRect()
          const hit = document.elementFromPoint(box.x + box.width / 2, box.y + box.height / 2)
          return !icon.contains(hit) && !["desktop-pet", "desktop-pet-static"].includes(hit?.id)
        })).map(icon => icon.textContent.trim())
      JS
    end

    # Which of the selection box's two drawings show, every 40ms for 800ms.
    def shown_drawings
      page.evaluate_async_script(<<~JS)
        const done = arguments[arguments.length - 1]
        const paths = [...document.querySelectorAll("#selection-box path")]
        const seen = []
        const look = () => {
          seen.push(paths.flatMap((path, i) => path.getAttribute("visibility") === "hidden" ? [] : [i]))
          seen.length < 20 ? setTimeout(look, 40) : done(seen)
        }
        look()
      JS
    end

    # For each corner of the selection box, in both drawings: how far past
    # the outer edge of the side it meets each side's stroke runs, and how far
    # short of that side's inner edge it stops (0 or less: it reaches in).
    def corner_fits
      page.evaluate_script(<<~JS)
        (() => {
          const box = document.getElementById("selection-box").getBoundingClientRect()
          const sides = d => d.split("M").filter(Boolean).map(side => side.replace("Z", "").split("L").map(point => point.trim().split(" ").map(Number)))
          const mean = (points, i) => points.reduce((sum, point) => sum + point[i], 0) / points.length
          return [...document.querySelectorAll("#selection-box path")].flatMap(path => {
            const all = sides(path.getAttribute("d"))
            return [[0, -1], [box.width, 1]].flatMap(([cx, sx]) => [[0, -1], [box.height, 1]].map(([cy, sy]) => {
              const across = all.find((side, i) => i % 2 === 0 && Math.abs(mean(side, 1) - cy) < 6).filter(([x]) => Math.abs(x - cx) < 8)
              const down = all.find((side, i) => i % 2 === 1 && Math.abs(mean(side, 0) - cx) < 6).filter(([, y]) => Math.abs(y - cy) < 8)
              const out = (points, i, s) => Math.max(...points.map(point => s * point[i]))
              const inner = (points, i, s) => Math.min(...points.map(point => s * point[i]))
              return [
                Math.max(out(across, 0, sx) - out(down, 0, sx), out(down, 1, sy) - out(across, 1, sy)),
                Math.max(inner(down, 0, sx) - out(across, 0, sx), inner(across, 1, sy) - out(down, 1, sy))
              ]
            }))
          })
        })()
      JS
    end

    def distance(a, b)
      Math.hypot(a[0] - b[0], a[1] - b[1])
    end

    # Drags an icon by an offset, or to a point, with a first small move past
    # the drag threshold.
    def drag(icon, by: nil, to: nil)
      x, y = icon_center(icon.text)
      to ||= [ x + by[0], y + by[1] ]
      page.driver.browser.action.move_to_location(x, y).click_and_hold
        .move_to_location(x + 10, y + 10).move_to_location(*to).release.perform
      assert_no_selector ".app.moving"
    end

    # A press on the wallpaper right of welcome.txt, below login.exe, and
    # above the bottom right group.
    def click_wallpaper
      page.driver.browser.action.move_to_location(1250, 700).click.perform
    end

    def wait_for_rock
      page.evaluate_async_script(<<~JS)
        const done = arguments[arguments.length - 1]
        const rock = document.getElementById("desktop-pet")
        rock.complete ? done() : rock.addEventListener("load", () => done(), { once: true })
      JS
    end

    def browser_window_size
      page.evaluate_script("[document.documentElement.clientWidth, document.documentElement.clientHeight]")
    end
end
