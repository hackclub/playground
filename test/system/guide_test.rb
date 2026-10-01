require "application_system_test_case"

# The guide in a real browser: guide.txt and welcome.txt's link open it in
# the guide window, it follows the reader's computer, its code copies, and
# its recordings play while they show.
class GuideSystemTest < ApplicationSystemTestCase
  SNIPPETS = Rails.root.join("app/views/guides/snippets")
  OS_STORE = "playground-guide-os".freeze

  teardown do
    @scripts&.each { page.driver.browser.execute_cdp("Page.removeScriptToEvaluateOnNewDocument", identifier: it) }
    page.driver.browser.execute_cdp("Emulation.setScriptExecutionDisabled", value: false)
    page.driver.browser.execute_cdp("Emulation.setEmulatedMedia", features: [])
  end

  test "guide.txt and welcome.txt's link open the guide in its window, which keeps to the guide" do
    forget_open_windows
    visit root_path
    # login.exe may lie over the link, beside welcome.txt, in front.
    close_login_window
    click_link "new to this? check out the guide!"
    within_frame(guide_frame) do
      assert_selector "h1", text: "Build a virtual pet in Godot"
      assert_no_link "← desktop"
      # Inside the window it offers the full-size guide in a new tab.
      new_tab = find_link("open the guide in a new tab ↗")
      assert_equal [ "/guide", "_blank" ], [ URI(new_tab[:href]).path, new_tab[:target] ]
    end
    within("#window-guide\\.txt .windowheader") { click_button "close", enable_aria_label: true }
    assert_no_selector "#window-guide\\.txt"

    find(".app", exact_text: "guide.txt").send_keys(:enter)
    within_frame(guide_frame) { assert_selector "h1", text: "Build a virtual pet in Godot" }
    # Its ship link opens ship.exe here, which for a visitor is the login in
    # login.exe, and the desktop doesn't load again.
    page.execute_script("document.documentElement.dataset.stillHere = ''")
    within_frame(guide_frame) { find_link("ship", exact_text: true).click }
    within_frame(find(".login-frame")) { assert_text "ship your desktop pet" }
    assert_no_selector "#window-goal\\.exe", visible: :all
    assert page.evaluate_script("'stillHere' in document.documentElement.dataset"), "the desktop did not reload"
    within_frame(guide_frame) { assert_equal "/guide", page.evaluate_script("location.pathname") }
  end

  test "on a phone the guide window fills the width" do
    resize_viewport_to(390, 844) do
      forget_open_windows
      visit root_path
      close_login_window
      click_link "new to this? check out the guide!"
      within_frame(guide_frame) { assert_selector "h1" }
      box = page.evaluate_script("document.getElementById('window-guide.txt').getBoundingClientRect().toJSON()")
      assert_equal [ 10, 370 ], [ box["left"], box["width"] ].map(&:round)
    end
  end

  test "a desktop saved when guide.txt said coming soon opens the guide again after a reload" do
    user = log_in_as("participant")
    visit dashboard_path
    page.execute_script("localStorage.setItem(arguments[0], arguments[1])", "playground-window-state:#{user.id}", [ { kind: "app", id: "guide.txt" } ].to_json)
    visit root_path
    within_frame(guide_frame) { assert_selector "h1", text: "Build a virtual pet in Godot" }
  end

  test "the guide opens on the reader's computer, by its platform or its user agent" do
    { "macOS" => "macos", "Windows" => "windows", "Linux" => "linux", "Chrome OS" => "linux" }.each do |platform, os|
      with_platform(%(Object.defineProperty(navigator, "userAgentData", { get: () => ({ platform: #{platform.to_json} }) })))
      visit guide_path
      assert_os os, "for a platform of #{platform}"
    end
    { "Mozilla/5.0 (Windows NT 10.0; Win64; x64)" => "windows", "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7)" => "macos",
      "Mozilla/5.0 (X11; Linux x86_64)" => "linux" }.each do |agent, os|
      with_platform(%(Object.defineProperty(navigator, "userAgentData", { get: () => undefined }); Object.defineProperty(navigator, "userAgent", { get: () => #{agent.to_json} })))
      visit guide_path
      assert_os os, "for #{agent}"
    end
  end

  test "the switch changes every shortcut and step, by mouse or keyboard, and the choice stays after a reload" do
    with_platform(%(Object.defineProperty(navigator, "userAgentData", { get: () => ({ platform: "macOS" }) })))
    visit guide_path
    page.execute_script("localStorage.removeItem(arguments[0])", OS_STORE)
    visit guide_path
    assert_os "macos"
    find(".os-switch label", text: "Linux").click
    assert_os "linux"
    # The arrow keys move along the switch, as for any radio buttons.
    find(".os-switch input[value=linux]", visible: :all).send_keys(:left)
    assert_os "windows"
    visit guide_path
    assert_os "windows"
    assert_equal "windows", page.evaluate_script("localStorage.getItem(arguments[0])", OS_STORE)
  end

  test "on its own page the guide has no new-tab link, and a chosen computer's step reads as part of the guide" do
    visit guide_path
    assert_no_link "open the guide in a new tab ↗"
    step = find(".os-step", visible: true)
    assert_equal [ "0px", "none" ], page.evaluate_script("(s => [getComputedStyle(s).borderTopWidth, getComputedStyle(s.querySelector('h3')).display])(arguments[0])", step)
    assert_no_text "on Windows you can"
  end

  test "without scripts, every computer's version shows, labelled, and the switch hides" do
    page.driver.browser.execute_cdp("Emulation.setScriptExecutionDisabled", value: true)
    visit guide_path
    assert_no_selector ".os-switch"
    assert_no_selector ".code-copy, .video-toggle"
    %w[macOS Windows Linux].each { assert_selector ".os-step h3", text: it }
    labels = [ "on macOS", "or", "on Windows and Linux" ]
    save, play = [ %w[⌘S Ctrl+S], labels ], [ %w[⌘B F5], labels ]
    assert_equal [ save, play, save, play, play ], shown_keys
  end

  test "each shell block's copy button copies its commands, and the GDScript can't be selected" do
    visit guide_path
    # The page's copies land here instead of the clipboard, which a headless
    # browser keeps to itself.
    page.execute_script("window.copied = []; navigator.clipboard.writeText = (text) => (window.copied.push(text), Promise.resolve())")
    buttons = all(".code-copy")
    assert_equal SNIPPETS.glob("*.sh").size, buttons.size
    buttons.each do |button|
      page.execute_script("arguments[0].scrollIntoView({ block: 'center' })", button)
      button.click
      assert_equal "copied ✓", button.text
    end
    shell = snippet_order.select { |name| SNIPPETS.glob("#{name}.sh").any? }
    expected = shell.map { |name| SNIPPETS.glob("#{name}.sh").first.read.split("\n").reject { it.start_with?("~") }.join("\n") }
    assert_equal expected, page.evaluate_script("window.copied")
    selects = page.evaluate_script("[...document.querySelectorAll('.code-block.no-copy pre')].map(pre => getComputedStyle(pre).userSelect)")
    assert_equal [ "none" ] * SNIPPETS.glob("*.gd").size, selects
  end

  test "a recording plays while it shows and pauses once scrolled away, and its button pauses it for good" do
    visit guide_path
    first = "document.querySelectorAll('.guide-video video')[0]"
    page.execute_script("#{first}.scrollIntoView({ block: 'center' })")
    assert_playing first, true
    page.execute_script("document.getElementById('your-own').scrollIntoView()")
    assert_playing first, false
    page.execute_script("#{first}.scrollIntoView({ block: 'center' })")
    assert_playing first, true
    toggle = find_all(".video-toggle").first
    toggle.click
    assert_playing first, false
    assert_equal "play", toggle.text
    assert_equal "play the recording", toggle["aria-label"]
    toggle.click
    assert_playing first, true
  end

  test "with reduced motion a recording waits on its poster until its play button" do
    page.driver.browser.execute_cdp("Emulation.setEmulatedMedia", features: [ { name: "prefers-reduced-motion", value: "reduce" } ])
    visit guide_path
    first = "document.querySelectorAll('.guide-video video')[0]"
    page.execute_script("#{first}.scrollIntoView({ block: 'center' })")
    sleep 0.5
    assert_playing first, false
    toggle = find_all(".video-toggle").first
    assert_equal "play", toggle.text
    assert_selector ".guide-video.paused", count: GuideHelper::VIDEOS.size
    toggle.click
    assert_playing first, true
  end

  private

  def guide_frame = find("#window-guide\\.txt iframe")

  def with_platform(source)
    @scripts ||= []
    @scripts.each { page.driver.browser.execute_cdp("Page.removeScriptToEvaluateOnNewDocument", identifier: it) }
    @scripts = [ page.driver.browser.execute_cdp("Page.addScriptToEvaluateOnNewDocument", source:)["identifier"] ]
    page.execute_script("try { localStorage.removeItem(arguments[0]) } catch {}", OS_STORE) if page.current_url.start_with?("http")
  end

  # The chosen computer, its radio button, the one step that shows, and each
  # shortcut's keys, with no label.
  def assert_os(os, message = nil)
    assert_selector ".guide[data-os-current=#{os}]", wait: 5
    assert_equal os, find(".os-switch input:checked", visible: :all)["value"], message
    assert_equal [ os ], all(".os-step").map { it["data-os"] }, message
    save, play = os == "macos" ? %w[⌘S ⌘B] : %w[Ctrl+S F5]
    assert_equal [ [ [ save ], [] ], [ [ play ], [] ], [ [ save ], [] ], [ [ play ], [] ], [ [ play ], [] ] ], shown_keys, message
  end

  # Each shortcut's keys that show, as drawn, and its labels that show.
  def shown_keys
    page.evaluate_script(<<~JS)
      [...document.querySelectorAll(".os-keys")].map(keys => [
        [...keys.querySelectorAll("kbd")].filter(kbd => kbd.offsetParent).map(kbd => (kbd.querySelector("[aria-hidden]") ?? kbd).textContent),
        [...keys.querySelectorAll(".os-label")].filter(label => label.offsetParent).map(label => label.textContent.trim())
      ])
    JS
  end

  def assert_playing(video, playing)
    page.document.synchronize do
      now = page.evaluate_script("!#{video}.paused")
      raise Capybara::ExpectationNotMet, "#{video} is #{"not " if playing}playing" unless now == playing
    end
  end

  # The snippets in the order the page shows them.
  def snippet_order
    Rails.root.join("app/views/guides/show.html.erb").read.scan(/guide_code "([\w-]+)"/).flatten
  end
end
