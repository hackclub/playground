require "application_system_test_case"

# A first visit's desktop: the flag top left, the logo and its line at the
# top in the middle, welcome.txt below them, and the taskbar. The built-in
# icons start in three groups: the files in a row under the flag, and a row
# in each bottom corner, the sponsor's bottom left and the trash's bottom
# right. Pets fill rows of three under the files, then columns at the right
# edge. A small desktop keeps its icons in rows under the flag, and a phone
# keeps its columns.
class InitialLayoutTest < ApplicationSystemTestCase
  DESKTOPS = [ [ 1920, 1080 ], [ 1440, 900 ], [ 1280, 720 ], [ 1024, 768 ] ].freeze
  # The sponsor's icon and Hack Club's four required links, by label.
  REQUIRED = [ "armand.sponsor", "Hack Club", "Terms & Privacy", "Fulfillment", "Security" ].freeze

  test "the icons start in three corner groups, and welcome.txt opens below the logo, clear of everything" do
    DESKTOPS.each do |size|
      resize_viewport_to(*size) do
        forget_open_windows
        visit root_path
        cells = icon_cells
        cols, rows = grid
        bottom = rows - 1
        assert_equal [ [ 0, 1 ], [ 1, 1 ], [ 2, 1 ] ], cells.values_at("welcome.txt", "guide.txt", "ship.exe"), "the files under the flag at #{size}"
        assert_equal [ 0, 2 ], cells["requirements.txt"], "the requirements under welcome.txt's icon at #{size}"
        assert_equal [ [ 0, bottom ], [ 1, bottom ], [ 2, bottom ] ], cells.values_at("armand.sponsor", "Fulfillment", "Security"), "bottom left at #{size}"
        assert_equal [ [ cols - 3, bottom ], [ cols - 2, bottom ], [ cols - 1, bottom ] ], cells.values_at("Terms & Privacy", "Hack Club", "trash"),
          "bottom right, with the trash in the corner, at #{size}"
        assert_sponsor_shows size

        welcome = box("#welcome")
        line = box(".background-logo-text")
        logo = box(".background-logo")
        assert_operator welcome["top"], :>=, line["bottom"], "below the logo's line at #{size}"
        assert_operator welcome["bottom"], :<=, taskbar_top, "above the taskbar at #{size}"
        assert_empty covered_icons("#welcome"), "welcome.txt covers no icon at #{size}"
        assert_empty covered_icons(".background-logo"), "the logo lies clear of the icons at #{size}"
        assert_empty covered_icons(".background-logo-text"), "its line lies clear of the icons at #{size}"
        assert_operator logo["left"], :>, rows_right, "the logo clears the files at #{size}"
      end
    end
  end

  test "welcome.txt opens large: down to the taskbar between the groups, or else just above the bottom ones" do
    [ [ 1920, 1080 ], [ 1440, 900 ], [ 1280, 720 ], [ 1024, 768 ], [ 1000, 600 ] ].each do |size|
      resize_viewport_to(*size) do
        forget_open_windows
        visit root_path
        welcome = box("#welcome")
        width = page.evaluate_script("document.documentElement.clientWidth")
        between = width - 2 * rows_right - 20
        assert_in_delta box(".background-logo-text")["bottom"] + 12, welcome["top"], 1, "under the tagline at #{size}"
        if between >= 480
          # Between the bottom groups, down to the taskbar, 54% of the screen wide up to 720px.
          assert_in_delta [ 720, (width * 0.54).round, between ].min, welcome["width"], 1, "as wide as it may be at #{size}"
          assert_in_delta taskbar_top - 10, welcome["bottom"], 1, "down to the taskbar at #{size}"
        else
          # Too narrow between them: it stops above the bottom groups, as wide as it likes.
          assert_in_delta [ 720, (width * 0.54).round ].min, welcome["width"], 1, "54% of the screen at #{size}"
          assert_operator welcome["bottom"], :<=, icon_box("armand.sponsor", ".appicon")["top"] - 9, "above the bottom groups at #{size}"
        end
        assert_empty covered_icons("#welcome"), "clear of the icons at #{size}"
      end
    end
  end

  test "the rock walks in front of the bottom left group, and never over the sponsor's icon" do
    forget_open_windows
    visit root_path
    # The rock starts over Fulfillment and Security, and walks 20px each way,
    # in front of them.
    rock = box("#desktop-pet")
    label = icon_box("Fulfillment", "p")
    assert_operator rock["left"] - 20, :<, label["right"]
    assert_operator rock["right"] + 20, :>, label["left"]
    assert_includes %w[desktop-pet desktop-pet-static], page.evaluate_script("document.elementFromPoint(arguments[0], arguments[1]).id",
      (rock["left"] + rock["width"] / 2).round, (rock["top"] + rock["height"] * 0.55).round)
    # What the rock draws, with its walk, stays clear of the sponsor's icon.
    sponsor = box(".app[data-key='armand.sponsor']")
    assert_operator rock["left"] + rock["width"] * 0.16 - 20, :>=, sponsor["right"]
    assert_sponsor_shows [ 1440, 900 ]
  end

  test "the rock draws in front of an open window" do
    forget_open_windows
    visit root_path
    rock = box("#desktop-pet")
    page.execute_script("Object.assign(document.getElementById('welcome').style, { left: '10px', top: (arguments[0] - 200) + 'px' })", rock["top"].round)
    assert_includes %w[desktop-pet desktop-pet-static], page.evaluate_script("document.elementFromPoint(arguments[0], arguments[1]).id",
      (rock["left"] + rock["width"] / 2).round, (rock["top"] + rock["height"] * 0.55).round)
    assert_equal "welcome", page.evaluate_script("document.elementFromPoint(arguments[0], arguments[1]).closest('.window')?.id",
      (rock["left"] + rock["width"] / 2).round, (rock["top"] + 8).round)
  end

  # Where the text row of the required links is hidden, their icons are the
  # only way to find them, so ship.exe after a login leaves them in sight,
  # with the sponsor's. It stops above the bottom groups instead.
  test "after a login, ship.exe leaves the sponsor and the four required links in sight" do
    user = log_in_as("participant")
    7.times { |i| user.projects.create!(name: "pet #{i + 1}", description: "a pet that naps") }
    [ [ 1440, 900 ], [ 1280, 720 ] ].each do |size|
      resize_viewport_to(*size) do
        forget_open_windows
        log_in_as("participant")
        within_frame(find(".ship-frame")) { assert_text "your meter" }
        page.document.synchronize do
          raise Capybara::ExpectationNotMet, "ship.exe is still being placed" if page.evaluate_script("!!document.querySelector('.window[data-placing]')")
        end
        assert_equal "none", page.evaluate_script("getComputedStyle(document.getElementById('credit-links')).display"), "the text row is hidden at #{size}"
        assert_empty covered_icons("#window-goal\\.exe") & REQUIRED, "ship.exe covers no required link at #{size}"
        assert_empty covered_icons("#welcome") & REQUIRED, "nor does welcome.txt at #{size}"
        assert_sponsor_shows size
        # Its page scrolls inside, above the bottom groups.
        assert_operator box("#window-goal\\.exe")["bottom"], :<=, icon_box("armand.sponsor", ".appicon")["top"]
      end
    end
  end

  test "a window a reload brings back over the required links comes back clear of them" do
    visit dashboard_path
    page.execute_script(<<~JS)
      localStorage.clear()
      localStorage.setItem("playground-window-state:visitor", JSON.stringify([{ kind: "app", id: "guide.txt", place: { left: 700, top: 600 } }]))
    JS
    visit root_path
    assert_selector "#window-guide\\.txt"
    page.document.synchronize do
      raise Capybara::ExpectationNotMet, "guide.txt is still being placed" if page.evaluate_script("!!document.querySelector('.window[data-placing]')")
    end
    assert_empty covered_icons("#window-guide\\.txt") & REQUIRED
    assert_sponsor_shows [ 1440, 900 ]
  end

  test "a welcome.txt the participant resized keeps its size through a reload" do
    forget_open_windows
    page.execute_script("localStorage.setItem('playground-window-places', JSON.stringify({ welcome: { left: 400, top: 200, width: 460, height: 300 } }))")
    visit root_path
    assert_equal [ 400, 200, 460, 300 ], box("#welcome").values_at("left", "top", "width", "height").map(&:round)
  end

  test "welcome.txt holds only its text, with no logo of its own" do
    visit root_path
    assert_no_selector "#welcomelogo"
    assert_no_selector "#welcome img[src*='landing/logo']"
    assert_selector "#welcome .windowcontent p", text: "make a desktop pet, ship it"
  end

  test "a long label takes two lines on a desktop, and one on a phone" do
    visit root_path
    assert_operator label_lines("Terms & Privacy"), :==, 2
    assert_operator label_lines("armand.sponsor"), :==, 2
    assert_operator label_lines("welcome.txt"), :==, 1
    resize_viewport_to(390, 844) do
      # On a phone the text row stands in for the link icons, so a pet with
      # the same long name shows the phone's label.
      log_in_as("participant").projects.create!(name: "Terms & Privacy")
      visit root_path
      assert_equal 1, label_lines("Terms & Privacy")
    end
  end

  test "pets fill rows of three under the files, then the right edge from the top, and never a group's cell" do
    user = log_in_as("participant")
    12.times { |i| user.projects.create!(name: "pet #{i + 1}") }
    resize_viewport_to(1440, 900) do
      forget_open_windows
      visit root_path
      cells = icon_cells
      cols, rows = grid
      # Rows of three between the files and the bottom left group, less the
      # requirements' cell, first in the first row.
      rows_pets = 3 * (rows - 3) - 1
      assert_equal (1..rows_pets).map { |i| [ i % 3, 2 + i / 3 ] }, (1..rows_pets).map { cells["pet #{it}"] },
        "the first pets fill rows of three under the files"
      edge = ((rows_pets + 1)..12).map { cells["pet #{it}"] }
      # The rest stack down the last column, from the top, above the trash.
      assert_equal edge.each_with_index.map { |_, i| [ cols - 1, i ] }, edge
      assert_operator edge.map(&:last).max, :<, rows - 1
      assert_equal 10 + 12, cells.values.uniq.size, "no two icons share a cell"
      assert_sponsor_shows [ 1440, 900 ]
    end
  end

  test "the banana peel, put back from the trash, takes the first free cell under the files" do
    forget_open_windows
    visit root_path
    find(".app[data-key=trash]").click
    within("#trash-menu") { click_button "restore banana peel" }
    assert_equal [ 1, 2 ], icon_cells["banana peel"]
  end

  test "an icon moved by hand keeps its spot, and the rest still start in their groups" do
    forget_open_windows
    visit root_path
    cols, rows = grid
    # The trash moved to the middle of the left edge, and saved there.
    page.execute_script("localStorage.setItem('playground-desktop-icons', JSON.stringify({ trash: [0, 3] }))")
    visit root_path
    cells = icon_cells
    assert_equal [ 0, 3 ], cells["trash"]
    assert_equal [ [ cols - 3, rows - 1 ], [ cols - 2, rows - 1 ] ], cells.values_at("Terms & Privacy", "Hack Club")
    assert_equal [ 0, rows - 1 ], cells["armand.sponsor"]
  end

  test "no other icon ever takes the sponsor's cell, even a saved one the screen pushed out" do
    forget_open_windows
    visit root_path
    _, rows = grid
    # The trash saved in a column past a small screen's edge.
    page.execute_script("localStorage.setItem('playground-desktop-icons', JSON.stringify({ trash: [13, arguments[0] - 1] }))", rows)
    resize_viewport_to(1024, 768) do
      visit root_path
      cells = icon_cells
      assert_equal [ 0, grid.last - 1 ], cells["armand.sponsor"]
      assert_not_equal cells["armand.sponsor"], cells["trash"]
      assert_sponsor_shows [ 1024, 768 ]
    end
  end

  test "a desktop too small for the groups keeps its icons in rows of three under the flag" do
    resize_viewport_to(640, 700) do
      forget_open_windows
      visit root_path
      cells = icon_cells
      # Here welcome.txt has no room beside three columns, so the rows take two.
      assert_equal [ [ 0, 1 ], [ 1, 1 ], [ 0, 2 ] ], cells.values_at("welcome.txt", "guide.txt", "ship.exe")
      cols, rows = grid
      assert_not_equal [ cols - 1, rows - 1 ], cells["trash"], "no group in the bottom right corner"
      assert_operator cells.values.map(&:first).max, :<, grid.first, "every icon on the grid"
    end
  end

  test "on a short screen, the sponsor still shows in its corner" do
    resize_viewport_to(1280, 600) do
      forget_open_windows
      visit root_path
      assert_operator icon_cells["armand.sponsor"].first, :<, 3
      assert_sponsor_shows [ 1280, 600 ]
    end
  end

  PHONES = [ [ 375, 667 ], [ 390, 844 ], [ 430, 932 ] ].freeze

  # login.exe, which every signed-out load opens, opens there too, in front.
  test "on a phone's first load, the flag, the text row, the logo and its line show whole, above welcome.txt and login.exe" do
    PHONES.each do |size|
      resize_viewport_to(*size) do
        forget_open_windows
        visit root_path
        assert_selector "#welcome"
        assert_selector "#window-login\\.exe"
        page.document.synchronize do
          raise Capybara::ExpectationNotMet, "login.exe is still being placed" if page.evaluate_script("!!document.querySelector('.window[data-placing]')")
        end
        logo, line = box(".background-logo"), box(".background-logo-text")
        assert_operator logo["left"], :>=, 0, "the logo fits at #{size}"
        assert_operator logo["right"], :<=, size[0], "the logo fits at #{size}"
        assert_operator logo["top"], :>=, box("#credits")["bottom"], "the logo sits below the text row at #{size}"
        { "welcome.txt" => "#welcome", "login.exe" => "#window-login\\.exe" }.each do |name, selector|
          window = box(selector)
          assert_operator window["top"], :>=, line["bottom"], "#{name} opens below the logo's line at #{size}"
          assert_operator window["bottom"], :<=, taskbar_top, "#{name} ends above the taskbar at #{size}"
        end
        assert_equal "window-login.exe", page.evaluate_script(<<~JS), "login.exe is in front at #{size}"
          [...document.querySelectorAll(".window")].filter(w => getComputedStyle(w).display !== "none")
            .sort((a, b) => getComputedStyle(a).zIndex - getComputedStyle(b).zIndex).pop().id
        JS
        # No window, and no icon's picture or label, covers the logo, the
        # words of its line, or the sponsor's name.
        [ ".background-logo", ".background-logo-text", "#credit-sponsor a" ].each do |part|
          assert page.evaluate_script(<<~JS, part), "#{part} shows at #{size}"
            (el => (b => [0.02, 0.5, 0.98].every(x => {
              const hit = document.elementFromPoint(b.left + b.width * x, b.top + b.height / 2)
              return !hit.closest(".window, .appicon, .app p")
            }))(el.tagName === "IMG" ? el.getBoundingClientRect() : (range => (range.selectNodeContents(el), range.getBoundingClientRect()))(document.createRange())))(document.querySelector(arguments[0]))
          JS
        end
        assert_equal "Armand", find("#credit-sponsor a").text
      end
    end
  end

  test "on a phone the icons lie in rows below the logo's line, never over the logo or its line" do
    user = log_in_as("participant")
    7.times { |i| user.projects.create!(name: "pet #{i + 1}") }
    PHONES.each do |size|
      resize_viewport_to(*size) do
        forget_open_windows
        visit root_path
        page.execute_script("document.querySelectorAll('.window').forEach(win => { if (getComputedStyle(win).display !== 'none') win.querySelector('.windowclose').click() })")
        cells = icon_cells
        top_row = cells.values.map(&:last).min
        assert_equal [ [ 0, top_row ], [ 1, top_row ] ], cells.values_at("welcome.txt", "guide.txt"), "rows from the left at #{size}"
        assert_empty covered_icons(".background-logo"), "no icon over the logo at #{size}"
        assert_empty covered_icons(".background-logo-text"), "no icon over its line at #{size}"
        assert_empty overlapping_icons, "no two icons share a spot at #{size}"
        # The five link icons stay hidden, for the text row.
        assert_empty all(".app[data-key='armand.sponsor'], .app[data-key='Hack Club']", visible: true)
      end
    end
  end

  test "a label whose word just fits shows it whole, and a longer word takes a smaller font" do
    user = log_in_as("participant")
    user.projects.create!(name: "Wolfeschlegel")
    forget_open_windows
    visit root_path
    # The clamp draws any ellipsis. A word a fraction of a pixel over its line clips instead.
    assert_equal [ "clip" ], page.evaluate_script("[...new Set([...document.querySelectorAll('.app p')].map(p => getComputedStyle(p).textOverflow))]")
    assert_equal 1, label_lines("Fulfillment")
    font, lines, whole = page.evaluate_script(<<~JS)
      (p => [parseFloat(getComputedStyle(p).fontSize), Math.round(p.getBoundingClientRect().height / (parseFloat(getComputedStyle(p).fontSize) * 1.25)), p.scrollWidth <= p.clientWidth + 1])(
        [...document.querySelectorAll(".app p")].find(p => p.textContent === "Wolfeschlegel"))
    JS
    assert_operator font, :<, 16, "the long word takes a smaller font"
    assert_operator font, :>=, 10
    assert_equal 1, lines, "and fits one line whole"
    assert whole
  end

  test "on a phone, many pets pack closer, and no two icons ever overlap" do
    user = log_in_as("participant")
    resize_viewport_to(390, 844) do
      [ 11, 15 ].each do |pets|
        (user.projects.count...pets).each { |i| user.projects.create!(name: "pet #{i + 1}") }
        forget_open_windows
        visit root_path
        find("#welcome .windowclose").send_keys(:enter)
        # The pets and five built-in icons: the text row stands in for the other five.
        assert_equal pets + 5, all(".app").size
        assert_empty overlapping_icons, "with #{pets} pets"
        assert page.evaluate_script(<<~JS), "every icon lies on the screen, above the taskbar, with #{pets} pets"
          (bar => [...document.querySelectorAll(".app")].every(icon => {
            const box = icon.getBoundingClientRect()
            return box.left >= 0 && box.right <= innerWidth && box.top >= 0 && box.bottom <= bar
          }))(document.getElementById("bar").getBoundingClientRect().top)
        JS
      end
    end
  end

  test "on a phone the logo and its line fit the screen's width" do
    resize_viewport_to(390, 844) do
      visit root_path
      [ ".background-logo", ".background-logo-text" ].each do |part|
        logo = box(part)
        assert_operator logo["left"], :>=, 0, "#{part} starts on the screen"
        assert_operator logo["right"], :<=, 390, "#{part} ends on the screen"
      end
      assert_equal 1, (box(".background-logo-text")["height"] / (page.evaluate_script("parseFloat(getComputedStyle(document.querySelector('.background-logo-text')).fontSize)") * 1.27)).round
    end
  end

  private

  # Each showing icon's cell. On a phone the icons that link off the site do not show.
  def icon_cells
    page.evaluate_script(<<~JS).to_h
      [...document.querySelectorAll(".app")].filter(icon => icon.offsetParent).map(icon => [icon.textContent.trim(), icon.dataset.cell.split(",").map(Number)])
    JS
  end

  def grid = find("#apps", visible: :all)["data-grid"].split.map(&:to_i)

  def box(selector) = page.evaluate_script("document.querySelector(arguments[0]).getBoundingClientRect().toJSON()", selector)

  def taskbar_top = page.evaluate_script("document.getElementById('bar').getBoundingClientRect().top")

  # The right edge of the icons' three columns.
  def rows_right
    cols, = grid
    page.evaluate_script("document.documentElement.clientWidth") / cols.to_f * 3
  end

  # Each pair of icons whose boxes overlap.
  def overlapping_icons
    page.evaluate_script(<<~JS)
      (icons => icons.flatMap((a, i) => icons.slice(i + 1).filter(b => {
        const x = a.getBoundingClientRect(), y = b.getBoundingClientRect()
        return x.left < y.right - 1 && y.left < x.right - 1 && x.top < y.bottom - 1 && y.top < x.bottom - 1
      }).map(b => [a.textContent.trim(), b.textContent.trim()])))([...document.querySelectorAll(".app")])
    JS
  end

  # The icons whose picture or label an element's box overlaps.
  def covered_icons(selector)
    page.evaluate_script(<<~JS, selector)
      (area => [...document.querySelectorAll(".app")].filter(icon =>
        [icon.querySelector(".appicon"), icon.querySelector("p")].some(part => {
          const b = part.getBoundingClientRect()
          return b.left < area.right - 1 && area.left < b.right - 1 && b.top < area.bottom - 1 && area.top < b.bottom - 1
        })).map(icon => icon.textContent.trim()))(document.querySelector(arguments[0]).getBoundingClientRect())
    JS
  end

  def label_lines(label)
    page.evaluate_script(<<~JS, label)
      (p => Math.round(p.getBoundingClientRect().height / parseFloat(getComputedStyle(p).lineHeight === "normal" ? 20 : getComputedStyle(p).lineHeight)))(
        [...document.querySelectorAll(".app p")].find(p => p.textContent === arguments[0] && p.offsetParent))
    JS
  end

  # The sponsor's icon sits in the rows and shows: a press on its picture
  # lands on it.
  # A part of an icon, by CSS selector.
  def icon_box(label, part)
    key = { "Fulfillment" => "Bounty" }.fetch(label, label)
    page.evaluate_script("document.querySelector(`[data-key=\"${arguments[0]}\"] ${arguments[1]}`).getBoundingClientRect().toJSON()", key, part)
  end

  # The sponsor's icon sits on the left, and shows: a press on its picture
  # lands on it, and neither welcome.txt nor the rock covers it.
  def assert_sponsor_shows(size)
    col, = icon_cells["armand.sponsor"]
    assert_operator col, :<, 3, "the sponsor's icon is on the left at #{size}"
    shows = page.evaluate_script(<<~JS)
      (icon => (b => icon.contains(document.elementFromPoint(b.left + b.width / 2, b.top + b.height / 2)))(icon.querySelector(".appicon").getBoundingClientRect()))(document.querySelector('[data-key="armand.sponsor"]'))
    JS
    assert shows, "the sponsor's icon shows at #{size}"
  end
end
