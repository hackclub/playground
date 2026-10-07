require "application_system_test_case"

# The new site's guide in steps in a real browser: it follows the reader's
# computer, its code copies, its recordings play while they show, and it goes
# from step to step, with old links to one long page landing on their step.
class NewSiteGuideSystemTest < ApplicationSystemTestCase
  include NewSiteTests
  SNIPPETS = Rails.root.join("app/views/guides/snippets")
  OS_STORE = "playground-guide-os".freeze

  teardown do
    @scripts&.each { page.driver.browser.execute_cdp("Page.removeScriptToEvaluateOnNewDocument", identifier: it) }
    page.driver.browser.execute_cdp("Emulation.setScriptExecutionDisabled", value: false)
    page.driver.browser.execute_cdp("Emulation.setEmulatedMedia", features: [])
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

  test "the note under a step changes every shortcut and step, and the choice stays after a reload" do
    with_platform(%(Object.defineProperty(navigator, "userAgentData", { get: () => ({ platform: "macOS" }) })))
    visit guide_path
    page.execute_script("localStorage.removeItem(arguments[0])", OS_STORE)
    visit guide_path
    assert_os "macos"
    first(".os-note button", text: "Linux").click
    assert_os "linux"
    first(".os-note button", text: "Windows").click
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
    assert_no_selector ".code-copy"
    %w[macOS Windows Linux].each { assert_selector ".os-step h3", text: it }
    labels = [ "on macOS", "or", "on Windows and Linux" ]
    save, play = [ %w[⌘S Ctrl+S], labels ], [ %w[⌘B F5], labels ]
    # The first step names saving and playing once each.
    assert_equal [ save, play ], shown_keys
  end

  test "each shell block's copy button copies its commands, and the GDScript can't be selected" do
    copied = []
    selects = []
    GuidePage.all.each do |step|
      visit step.path
      # The page's copies land here instead of the clipboard, which a headless
      # browser keeps to itself.
      page.execute_script("window.copied = []; navigator.clipboard.writeText = (text) => (window.copied.push(text), Promise.resolve())")
      all(".code-copy").each do |button|
        page.execute_script("arguments[0].scrollIntoView({ block: 'center' })", button)
        button.click
        assert_equal "copied ✓", button.text
      end
      copied.concat(page.evaluate_script("window.copied"))
      selects.concat(page.evaluate_script("[...document.querySelectorAll('.code-block.no-copy pre')].map(pre => getComputedStyle(pre).userSelect)"))
    end
    shell = snippet_order.select { |name| SNIPPETS.glob("#{name}.sh").any? }
    assert_equal SNIPPETS.glob("*.sh").size, shell.size
    expected = shell.map { |name| SNIPPETS.glob("#{name}.sh").first.read.split("\n").reject { it.start_with?("~") }.join("\n") }
    assert_equal expected, copied
    assert_equal [ "none" ] * SNIPPETS.glob("*.gd").size, selects
  end

  test "a recording plays while it shows and pauses once scrolled away, and a click on it pauses it for good" do
    visit guide_path
    first = "document.querySelectorAll('.guide-video video')[0]"
    page.execute_script("#{first}.scrollIntoView({ block: 'center' })")
    assert_playing first, true
    page.execute_script("document.getElementById('commands').scrollIntoView()")
    assert_playing first, false
    page.execute_script("#{first}.scrollIntoView({ block: 'center' })")
    assert_playing first, true
    video = find_all(".guide-video video").first
    video.click
    assert_playing first, false
    assert_equal "click to play", video["title"]
    video.click
    assert_playing first, true
  end

  test "with reduced motion a recording waits on its poster until a click plays it" do
    page.driver.browser.execute_cdp("Emulation.setEmulatedMedia", features: [ { name: "prefers-reduced-motion", value: "reduce" } ])
    visit guide_path
    first = "document.querySelectorAll('.guide-video video')[0]"
    page.execute_script("#{first}.scrollIntoView({ block: 'center' })")
    sleep 0.5
    assert_playing first, false
    assert_selector ".guide-video.paused", count: all(".guide-video").size
    find_all(".guide-video video").first.click
    assert_playing first, true
  end

  test "an old link to the one long page lands on the step that holds its anchor, at that anchor" do
    { "movement" => "/guide/move", "pick-step" => "/guide/move", "pick-project" => "/guide/move", "transparent" => "/guide/scene", "drag" => "/guide/animate" }.each do |anchor, path|
      visit "/guide##{anchor}"
      assert_selector "article.guide ##{anchor}"
      assert_equal "#{path}##{anchor}", page.evaluate_script("location.pathname + location.hash")
      assert_near_top "##{anchor}"
    end
    # The ship step is near the bottom of the last step, so it shows, as far
    # down as the page scrolls.
    visit "/guide#ship-step"
    assert_equal "/guide/publish#ship-step", page.evaluate_script("location.pathname + location.hash")
    assert page.evaluate_script("(r => r.top >= 0 && r.top < innerHeight)(document.getElementById('ship-step').getBoundingClientRect())")
    # An anchor on the first step, or on no step, stays on /guide.
    visit "/guide#commands"
    assert_selector "#commands"
    assert_equal "/guide#commands", page.evaluate_script("location.pathname + location.hash")
    visit "/guide#nothing-here"
    assert_selector "#guide"
    assert_equal "/guide", page.evaluate_script("location.pathname")
  end

  test "the buttons under the guide go to the step before and after, each landing at the top of its step" do
    visit "/guide/setup"
    assert_no_selector ".guide-prev"
    page.execute_script("scrollTo(0, document.documentElement.scrollHeight)")
    find(".guide-next", text: "Build the scene").click
    assert_selector "h2#start"
    assert_equal "/guide/scene", page.evaluate_script("location.pathname")
    assert_equal 0, page.evaluate_script("scrollY")
    assert_selector ".hub-outline .outline-step > a[aria-current=page]", text: "Build the scene"
    find(".guide-prev", text: "Set up").click
    assert_selector "h2#setup-godot"
    assert_equal "/guide/setup", page.evaluate_script("location.pathname")
    # The browser's back button goes back a step.
    page.go_back
    assert_selector "h2#start"
    visit "/guide/publish"
    assert_no_selector ".guide-next"
    assert_selector ".guide-prev", text: "Animate and drag"
  end

  test "on a phone, a step lands at the top of the guide, below the next step and the hours" do
    visit dev_login_path(as: "participant")
    assert_selector "#guide"
    resize_viewport_to(390, 844) do
      visit "/guide/setup"
      page.execute_script("scrollTo(0, document.documentElement.scrollHeight)")
      find(".guide-next").click
      assert_selector "h2#start"
      assert_near_top "#guide"
      assert_operator page.evaluate_script("scrollY"), :>, 100, "the next step and the hours stand above the guide"
      assert_equal 390, page.evaluate_script("document.documentElement.scrollWidth")
      # The list of steps in the guide goes there too.
      page.execute_script("scrollTo(0, 0)")
      find(".guide-contents a", text: "Make it move").click
      assert_selector "h2#movement"
      assert_near_top "#guide"
    end
  end

  test "the next step card's link goes to its step, at its part, and the card hides there" do
    visit dev_login_path(as: "newbie")
    assert_selector "#guide"
    visit "/guide/setup"
    card = find("#hub-next .side-next")
    href = card.find("a.btn")[:href]
    path, anchor = URI(href).then { [ it.path, it.fragment ] }
    assert_equal GuidePage.href(anchor), "#{path}##{anchor}"
    card.find("a.btn").click
    assert_selector "article.guide ##{anchor}"
    assert_equal "#{path}##{anchor}", page.evaluate_script("location.pathname + location.hash")
    assert_selector "#hub-next .side-next", visible: :hidden
  end

  test "at the bottom of each step the outline marks its last section, and a click or a link to a section marks it" do
    GuidePage.all.each do |step|
      visit step.path
      assert_selector ".hub-outline ol ol a"
      page.execute_script("scrollTo(0, document.documentElement.scrollHeight)")
      last = all(".hub-outline ol ol a").last.text
      assert_selector ".hub-outline ol ol a.current", text: last, exact_text: true
      assert_selector ".hub-outline ol ol a.current", count: 1
    end
    visit "/guide/setup"
    page.execute_script("scrollTo(0, document.documentElement.scrollHeight)")
    find(".hub-outline ol ol a", exact_text: "Important commands").click
    assert_selector ".hub-outline ol ol a.current", exact_text: "Important commands"
    assert_equal "#commands", page.evaluate_script("location.hash")
    # A link to a part marks its section, as the next step card's does.
    visit "/guide/move#pick-project"
    assert_selector ".hub-outline ol ol a.current", exact_text: "Pick your pet's project"
    visit "/guide/move#pick-step"
    assert_selector ".hub-outline ol ol a.current", exact_text: "Pick your pet's project"
  end

  private

  def with_platform(source)
    @scripts ||= []
    @scripts.each { page.driver.browser.execute_cdp("Page.removeScriptToEvaluateOnNewDocument", identifier: it) }
    @scripts = [ page.driver.browser.execute_cdp("Page.addScriptToEvaluateOnNewDocument", source:)["identifier"] ]
    page.execute_script("try { localStorage.removeItem(arguments[0]) } catch {}", OS_STORE) if page.current_url.start_with?("http")
  end

  # On the first step: the chosen computer, the one step that shows, and
  # each shortcut's keys, with no label.
  def assert_os(os, message = nil)
    assert_selector ".guide[data-os-current=#{os}]", wait: 5
    assert_equal [ os ], all(".os-step").map { it["data-os"] }, message
    save, play = os == "macos" ? %w[⌘S ⌘B] : %w[Ctrl+S F5]
    assert_equal [ [ [ save ], [] ], [ [ play ], [] ] ], shown_keys, message
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

  # The element's top is at the top of the window, give or take its scroll
  # margin, once the page has scrolled there.
  def assert_near_top(selector)
    page.document.synchronize do
      top = page.evaluate_script("document.querySelector(arguments[0]).getBoundingClientRect().top", selector)
      raise Capybara::ExpectationNotMet, "#{selector} is #{top}px from the top" unless top.between?(-2, 26)
    end
  end

  def assert_playing(video, playing)
    page.document.synchronize do
      now = page.evaluate_script("!#{video}.paused")
      raise Capybara::ExpectationNotMet, "#{video} is #{"not " if playing}playing" unless now == playing
    end
  end

  # The snippets in the order the guide's steps show them.
  def snippet_order
    GuidePage.all.flat_map { Rails.root.join("app/views/guides/pages/_#{it.slug}.html.erb").read.scan(/guide_code "([\w-]+)"/).flatten }
  end
end
