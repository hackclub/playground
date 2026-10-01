require "application_system_test_case"

# Screenshots are added, moved, replaced, and removed in a grid of six cells
# on the edit page, and ship.exe offers the same grid while a pet has none.
# The whole grid takes a drop. Each change saves at once and only the grid
# changes, so the form keeps what was typed. The pet page shows the saved
# screenshots and nothing to upload with.
class ScreenshotUploadsTest < ApplicationSystemTestCase
  # Stored screenshots load from this app, so the browser can draw them. The
  # key in the query makes each upload a new, uncached URL.
  class LocalStore < MemoryScreenshotStore
    def url(key) = "#{Capybara.current_session.server.base_url}/icon.png?#{key}"
  end

  class BrokenStore < LocalStore
    def put(*) = raise(ScreenshotStore::NotConfigured, "screenshot storage isn't set up yet")
  end

  setup do
    ScreenshotStore.current = LocalStore.new
    # The upload sends the page's CSRF token, which only renders with this on.
    ActionController::Base.allow_forgery_protection = true
    log_in_as "participant"
    @project = User.find_by!(hca_id: "ident!dev-participant").projects.create!(name: "rock", description: "naps on your windows")
    @files = []
    @shot = image_file("shot", 1280, 720)
    page.current_window.resize_to(1024, 600)
  end

  teardown do
    ActionController::Base.allow_forgery_protection = false
    page.current_window.resize_to(1440, 900)
    @files.each(&:unlink)
  end

  test "files chosen together upload in turn, and one that fails says which while the others land" do
    visit edit_project_path(@project)
    tiny = image_file("tiny", 320, 200)
    choose_files @shot, tiny, image_file("second", 1600, 900)
    assert_selector ".thumb:not(.pending)", count: 2
    assert_selector ".upload-status.alert", text: "#{File.basename(tiny.path)}: this image is 320×200. screenshots must be at least 640×360."
    assert_no_selector ".thumb.pending"
    shots = @project.reload.screenshots
    assert_equal 2, shots.size
    assert_equal shots.pluck("id"), all(".thumb").map { it["data-id"] }
    assert_equal [ "screenshot 1 of 2, the cover", "screenshot 2 of 2" ], all(".thumb").map { it["aria-label"] }
    assert_selector ".thumb.cover", count: 1
    assert_grid filled: 2
  end

  test "a screenshot moves by the arrow keys or by drag, and the first is the cover" do
    ids = add_screenshots(3)
    visit edit_project_path(@project)
    thumb(ids[2]).send_keys(:left, :left)
    assert_selector ".upload-status", text: "moved to 1 of 3"
    assert_equal [ ids[2], ids[0], ids[1] ], saved_order
    assert_equal "screenshot 1 of 3, the cover", page.evaluate_script("document.activeElement.getAttribute('aria-label')")
    assert_selector ".thumb.cover[data-id='#{ids[2]}']"

    # A drag of the cover past the last one's middle puts it last.
    last = thumb(ids[1])
    page.driver.browser.action.click_and_hold(thumb(ids[2]).native).move_by(12, 0)
      .move_to(last.native, (last.rect.width / 4).round, 0).release.perform
    assert_equal [ ids[0], ids[1], ids[2] ], saved_order
    assert_selector ".thumb.cover[data-id='#{ids[0]}']"
  end

  test "Enter or a click replaces a screenshot in its place, and its × or Delete removes one, the last too" do
    ids = add_screenshots(2)
    visit edit_project_path(@project)
    fill_in "project[name]", with: "renamed rock"
    thumb(ids[1]).send_keys(:enter)
    choose_files @shot
    assert_text "uploaded ✓"
    now = @project.reload.screenshots.pluck("id")
    assert_equal ids[0], now[0]
    assert_not_equal ids[1], now[1]
    assert_selector ".thumb[data-id='#{now[1]}'] img[src$='#{@project.screenshots[1]["key"]}']"

    click_button "remove screenshot 2", enable_aria_label: true
    assert_text "removed ✓"
    assert_selector ".thumb", count: 1
    thumb(now[0]).send_keys(:delete)
    assert_no_selector ".thumb"
    assert_grid filled: 0
    assert_empty @project.reload.screenshots
    assert_field "project[name]", with: "renamed rock"

    visit checks_project_path(@project)
    assert_selector "#ship-check-screenshot.todo", text: "your pet needs a screenshot"
  end

  test "a pet holds up to six: the last cell fills, the add cell goes, and a drop on the full grid says so" do
    add_screenshots(ScreenshotLimits::PER_PET - 1)
    visit edit_project_path(@project)
    assert_grid filled: 5
    extra = image_file("extra", 1280, 720)
    choose_files @shot, extra
    assert_selector ".thumb:not(.pending)", count: ScreenshotLimits::PER_PET
    assert_selector ".upload-status.alert", text: "#{File.basename(extra.path)}: a pet holds up to 6 screenshots. remove one to add another."
    assert_grid filled: 6
    assert_equal ScreenshotLimits::PER_PET, @project.reload.screenshots.size

    drop_files_on ".shots-grid", name: "more.png"
    assert_selector ".upload-status.alert", text: "more.png: a pet holds up to 6 screenshots. remove one to add another."
    assert_equal ScreenshotLimits::PER_PET, @project.reload.screenshots.size
  end

  test "each screenshot fills its cell edge to edge, whatever its shape" do
    shapes = { "landscape" => [ 1280, 720 ], "portrait" => [ 900, 1200 ], "wide" => [ 2560, 640 ], "square" => [ 1000, 1000 ] }
    @project.update_columns(screenshots: shapes.map { |name, (width, height)| inline_shot(name, width, height) })
    visit edit_project_path(@project)
    assert_grid filled: 4
    page.document.synchronize { raise Capybara::ExpectationNotMet, "images loading" unless page.evaluate_script("[...document.querySelectorAll('.thumb img')].every((img) => img.complete && img.naturalWidth)") }
    cells = page.evaluate_script(<<~JS)
      [...document.querySelectorAll(".thumb")].map((cell) => {
        const img = cell.querySelector("img")
        return { cell: cell.getBoundingClientRect().toJSON(), img: img.getBoundingClientRect().toJSON(), fit: getComputedStyle(img).objectFit, size: [img.naturalWidth, img.naturalHeight] }
      })
    JS
    assert_equal shapes.values, cells.pluck("size")
    cells.zip(shapes.keys).each do |measured, shape|
      assert_equal "cover", measured["fit"], shape
      %w[left top right bottom].each do |edge|
        assert_in_delta measured["cell"][edge], measured["img"][edge], 0.5, "the #{shape} screenshot's #{edge} edge is its cell's"
      end
    end
    widths = cells.map { it["cell"]["width"] }
    assert_in_delta widths.min, widths.max, 0.5, "the cells are equal"
  end

  test "the next free cell adds screenshots by click, Enter, or Space, and the other free cells are empty" do
    add_screenshots(2)
    visit edit_project_path(@project)
    assert_grid filled: 2
    assert_selector ".shot-cell.add:nth-child(2)", text: "add screenshots" do |add|
      assert_equal "button", add[:role]
    end
    cells = page.evaluate_script("[...document.querySelector('.shots-grid').children].flatMap(c => c.matches('ol') ? [...c.children] : [c]).filter(c => !c.hidden).map(c => c.className)")
    assert_equal [ "shot-cell thumb cover", "shot-cell thumb", "shot-cell add", "shot-cell empty", "shot-cell empty", "shot-cell empty" ], cells
    page.execute_script("window.picked = 0; document.querySelector('input[type=file]').click = () => window.picked++")
    add = find(".shot-cell.add")
    add.click
    add.send_keys(:enter)
    add.send_keys(:space)
    assert_equal 3, page.evaluate_script("window.picked")
  end

  test "files dragged over the grid tint it, one over a screenshot says it replaces it, and a drop anywhere adds" do
    ids = add_screenshots(1)
    visit edit_project_path(@project)
    drag_files_over ".shot-cell.empty:not([hidden])"
    assert_selector ".shots-grid.dropping"
    assert_no_selector ".thumb.hover"
    drag_files_over ".thumb[data-id='#{ids[0]}']"
    assert_selector ".thumb.hover[data-id='#{ids[0]}']"
    assert_equal '"replace"', page.evaluate_script("getComputedStyle(document.querySelector('.thumb.hover'), '::before').content")
    page.execute_script("document.querySelector('.thumb.hover').dispatchEvent(new DragEvent('dragleave', { bubbles: true, dataTransfer: window.dragged }))")
    page.execute_script("document.querySelector('.shot-cell.empty:not([hidden])').dispatchEvent(new DragEvent('dragleave', { bubbles: true, dataTransfer: window.dragged }))")
    assert_no_selector ".shots-grid.dropping"
    assert_no_selector ".thumb.hover"

    # A drag that holds no files, such as text, changes nothing.
    page.execute_script(<<~JS)
      const text = new DataTransfer()
      text.setData("text/plain", "not a file")
      document.querySelector(".shot-cell.empty:not([hidden])").dispatchEvent(new DragEvent("dragenter", { bubbles: true, dataTransfer: text }))
    JS
    assert_no_selector ".shots-grid.dropping"

    drop_files_on ".shot-cell.empty:not([hidden])", name: "dropped.png", width: 1280, height: 720
    assert_text "uploaded ✓"
    assert_no_selector ".shots-grid.dropping"
    assert_equal 2, @project.reload.screenshots.size
    assert_equal ids[0], @project.screenshots.first["id"], "a drop beside a screenshot adds, and the cover stays"
  end

  test "on the edit page, an upload adds in place and keeps what was typed" do
    visit edit_project_path(@project)
    assert_upload_in_place
    click_button "save"
    assert_selector "h2", text: "renamed rock"
    assert_selector "img.shot[src$='#{@project.reload.screenshots.first["key"]}']"
    assert_no_text "your pet needs a screenshot"
  end

  test "in the pet's window, the edit page uploads in place and keeps the window styling" do
    visit root_path(open: "goal")
    within_frame(find(".ship-frame")) do
      # At this height the desktop pet covers the foot of ship.exe, and the
      # desktop does not scroll, so the link opens from the keyboard.
      find_link("edit", href: edit_project_path(@project)).send_keys(:enter)
    end
    within_frame(find("#window-pet-#{@project.id} iframe")) do
      assert_upload_in_place
      assert_selector "body.in-window"
    end
  end

  test "the pet page shows the screenshots, with nothing to upload or replace them with" do
    visit project_path(@project)
    assert_text "no screenshot yet"
    assert_no_upload_control

    add_screenshots(1)
    visit project_path(@project)
    assert_selector "h2", exact_text: "screenshot"
    assert_selector "img.shot[src$='#{@project.screenshots.first["key"]}']"
    assert_no_text "no screenshot yet"
    assert_no_upload_control
  end

  test "the grid only offers to add screenshots, and says the rules when a file breaks one" do
    visit edit_project_path(@project)
    assert_grid filled: 0
    assert_selector ".shot-cell.add", exact_text: "add screenshots"
    assert_no_text "drop"
    assert_no_text "at least"

    notes = Tempfile.new([ "notes", ".txt" ]).tap { it.write("not a picture"); it.close }
    @files << notes
    choose_files notes
    assert_selector ".upload-status.alert", text: "use a PNG, JPEG, or WebP screenshot."

    choose_files image_file("tiny", 320, 200)
    assert_selector ".upload-status.alert", text: "this image is 320×200. screenshots must be at least 640×360."
    assert_no_selector ".thumb"
  end

  private

  def image_file(name, width, height)
    Tempfile.new([ name, ".png" ]).tap { it.binmode; it.write(image_bytes(width, height)); it.close }.tap { @files << it }
  end

  def choose_files(*files)
    paths = files.map(&:path)
    find("input[type=file]", visible: :hidden).set(paths.one? ? paths.first : paths)
  end

  def add_screenshots(count)
    shots = Array.new(count) { |n| { "id" => SecureRandom.uuid, "key" => "saved-#{n}.webp", "url" => ScreenshotStore.current.url("saved-#{n}.webp") } }
    @project.update!(screenshots: @project.screenshots + shots)
    shots.pluck("id")
  end

  def thumb(id) = find(".thumb[data-id='#{id}']")

  # A screenshot of one solid colour and the given shape, drawn into the page.
  def inline_shot(name, width, height)
    { "id" => name, "key" => "#{name}.png", "url" => "data:image/png;base64,#{Base64.strict_encode64(image_bytes(width, height))}" }
  end

  # Six cells: the screenshots, then the add cell while there is room, then
  # empty cells for the rest.
  def assert_grid(filled:)
    assert_selector ".shots-grid .thumb", count: filled
    assert_selector ".shots-grid .shot-cell.add", count: filled < ScreenshotLimits::PER_PET ? 1 : 0
    assert_selector ".shots-grid .shot-cell.empty", count: [ ScreenshotLimits::PER_PET - filled - 1, 0 ].max
    assert_selector ".shots-grid .shot-cell", count: ScreenshotLimits::PER_PET
  end

  # A browser test can't drag a file from the desktop, so these send the
  # drag's events with a file made in the page, as the browser would.
  def drag_files_over(selector)
    page.execute_script(<<~JS, selector)
      window.dragged ??= (() => { const files = new DataTransfer(); files.items.add(new File(["x"], "shot.png", { type: "image/png" })); return files })()
      const cell = document.querySelector(arguments[0])
      for (const type of ["dragenter", "dragover"]) cell.dispatchEvent(new DragEvent(type, { bubbles: true, cancelable: true, dataTransfer: window.dragged }))
    JS
  end

  def drop_files_on(selector, name:, width: 1280, height: 720)
    page.execute_script(<<~JS, selector, name, width, height)
      const [selector, name, width, height] = arguments
      const canvas = Object.assign(document.createElement("canvas"), { width, height })
      canvas.getContext("2d").fillRect(0, 0, width, height)
      canvas.toBlob((blob) => {
        const files = new DataTransfer()
        files.items.add(new File([ blob ], name, { type: "image/png" }))
        const cell = document.querySelector(selector)
        for (const type of ["dragenter", "dragover", "drop"]) cell.dispatchEvent(new DragEvent(type, { bubbles: true, cancelable: true, dataTransfer: files }))
      }, "image/png")
    JS
  end

  # The order the server holds, once the page's last save is in.
  def saved_order
    shown = all(".thumb").map { it["data-id"] }
    page.document.synchronize { raise Capybara::ElementNotFound unless @project.reload.screenshots.pluck("id") == shown }
    shown
  end

  def assert_no_upload_control
    assert_no_selector "input[type=file], .shots-grid, [data-controller~='screenshot-upload']", visible: :all
  end

  # A failed upload after this one leaves the list as it was.
  def assert_upload_in_place
    fill_in "project[name]", with: "renamed rock"
    page.execute_script("window.samePage = true")
    choose_files @shot
    assert_text "uploaded ✓"
    saved = ".thumb img[src$='#{@project.reload.screenshots.sole["key"]}']"
    assert_selector saved
    assert page.evaluate_script("window.samePage"), "the page did not reload"
    assert_field "project[name]", with: "renamed rock"
    assert_equal "rock", @project.name, "the typed name waits for save"

    ScreenshotStore.current = BrokenStore.new
    choose_files @shot
    assert_text "screenshot storage isn't set up yet"
    assert_selector saved
    assert_selector ".thumb", count: 1
    ScreenshotStore.current = LocalStore.new
  end
end
