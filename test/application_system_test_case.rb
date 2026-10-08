require "test_helper"

class ApplicationSystemTestCase < ActionDispatch::SystemTestCase
  # Existing system tests explicitly cover the legacy desktop for guests.
  # New-site tests opt in during setup; teardown restores the visitor default.
  setup { NewSite.for_visitors = false }
  teardown { NewSite.for_visitors = true }

  # Locally the tests run in Chrome for Testing, which Selenium Manager fetches
  # and caches, so they need no installed Chrome. CI uses its own Chrome. Rails
  # resolves the driver path up front, after which Selenium never looks up a
  # browser, so the binary comes from Selenium Manager here.
  driven_by :selenium, using: :headless_chrome, screen_size: [ 1440, 900 ] do |options|
    unless ENV["CI"]
      paths = Selenium::WebDriver::SeleniumManager.binary_paths("--browser", "chrome", "--browser-version", "stable")
      options.binary = paths["browser_path"]
    end
  end

  # One browser for every two cores. One per core loads the machine so far
  # that the suite runs slower, and a save's round trip can outlast a wait.
  # This file loads only with the system tests, so the other tests keep one
  # worker per core. PARALLEL_WORKERS still sets the count.
  parallelize(workers: [ (Concurrent.available_processor_count || Concurrent.processor_count).floor / 2, 1 ].max)

  # Under load a save's round trip can outlast Capybara's 2s default. A
  # passing check returns as soon as it passes, so the longer wait only costs
  # time when a test fails.
  Capybara.default_max_wait_time = 5

  # A viewport set by resize_viewport_to stays with the browser, which the
  # next test reuses, so each test ends by giving the browser its own back.
  # Windows open where the screen has room, so a leftover size moves them.
  teardown { page.driver.browser.execute_cdp("Emulation.clearDeviceMetricsOverride") }

  # The login's button shows only with a Hack Club Auth app, and makes the
  # login taller. A test whose layout depends on the login's height sets
  # that there is none, whatever the machine's credentials hold, and each
  # test ends by taking the setting back.
  def without_hack_club_app
    Rails.application.credentials.define_singleton_method(:dig) { |*keys| keys == %i[hack_club client_id] ? nil : options.dig(*keys) }
  end

  teardown do
    credentials = Rails.application.credentials
    credentials.singleton_class.remove_method(:dig) if credentials.singleton_methods.include?(:dig)
  end

  # A dev login runs the whole chain, fake Hackatime included, and ends on
  # the desktop. Waiting for the desktop keeps the next visit from racing it.
  def log_in_as(kind)
    visit dev_login_path(as: kind)
    assert_selector "#welcome"
    User.find_by!(hca_id: "ident!dev-#{kind}")
  end

  # A click in a desktop window whose answer reloads the whole desktop, as
  # log out and the logins in ship.exe do. The reload can take the window's
  # frame, and the button in it, while the browser is still finishing the
  # click, and the browser then says the node is gone. That counts as the
  # click having landed. What shows it did is a new desktop: the old one is
  # marked first, and the wait ends only on a loaded desktop without the
  # mark, so a click that never happened, or one that reloads nothing, still
  # fails. Pages come and go on the way, as a login passes through
  # Hackatime, so a look that catches one going is taken again.
  GONE = /does not belong to the document|stale element|no such frame|frame (?:was )?detached|execution context/i

  def click_reloading_the_desktop
    page.execute_script("document.documentElement.dataset.oldDesktop = ''")
    begin
      yield
    rescue Selenium::WebDriver::Error::WebDriverError => e
      raise unless e.message.match?(GONE)
      page.driver.browser.switch_to.default_content
    end
    page.document.synchronize(Capybara.default_max_wait_time, errors: [ Capybara::ExpectationNotMet, Selenium::WebDriver::Error::WebDriverError ]) do
      new_desktop = page.evaluate_script(<<~JS)
        !("oldDesktop" in document.documentElement.dataset) && document.readyState === "complete" && !!document.getElementById("welcome")
      JS
      raise Capybara::ExpectationNotMet, "the desktop did not reload" unless new_desktop
    end
  end

  # A reload brings back the desktop's open windows, so a test that needs a
  # first visit's desktop again forgets them, from a page that saves none.
  def forget_open_windows
    visit dashboard_path
    page.execute_script(<<~JS)
      Object.keys(localStorage).filter(key => key.startsWith("playground-window-state")).forEach(key => localStorage.removeItem(key))
    JS
  end

  # A visitor's first visit opens login.exe over the desktop. A test of the
  # rest of the desktop closes it, and a reload keeps it closed.
  def close_login_window
    within("#window-login\\.exe .windowheader") { click_button "close", enable_aria_label: true }
    assert_no_selector "#window-login\\.exe"
  end

  # welcome.txt opens large on a desktop, under the logo. A test that moves
  # it about gives it back its own smaller size, 500px by at most 400px.
  def welcome_at_own_size
    page.execute_script("(w => { w.style.width = ''; w.style.removeProperty('--window-max-height') })(document.getElementById('welcome'))")
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

  # Sizes the page, as the browser's device emulation does, since the browser
  # keeps its window at least 500px wide. With a block it puts the 1440x900
  # page back after.
  def resize_viewport_to(width, height, scale: 1)
    page.driver.browser.execute_cdp("Emulation.setDeviceMetricsOverride", width:, height:, deviceScaleFactor: scale, mobile: false)
    return unless block_given?
    begin
      yield
    ensure
      resize_viewport_to(1440, 900)
    end
  end
end

# Tests of how far readers get in the guides (GuideSections): a heading
# counts after half a second in view, and a page reports every second. A
# reader's time (GuideJourneyDay) stops 2 seconds after they last did
# anything, and a "minute" of it lasts a second.
module GuideProgressTests
  extend ActiveSupport::Concern

  included do
    setup do
      @progress = [ GuideSections.reach_seconds, GuideSections.send_seconds, GuideJourneyDay.idle_seconds, GuideJourneyDay.minute_seconds ]
      GuideSections.reach_seconds = 0.5
      GuideSections.send_seconds = 1
      GuideJourneyDay.idle_seconds = 2
      GuideJourneyDay.minute_seconds = 1
      # The reports send the page's CSRF token, which only renders with this on.
      ActionController::Base.allow_forgery_protection = true
    end

    teardown do
      GuideSections.reach_seconds, GuideSections.send_seconds, GuideJourneyDay.idle_seconds, GuideJourneyDay.minute_seconds = @progress
      ActionController::Base.allow_forgery_protection = false
    end
  end

  def counted(guide, section) = GuideSectionDay.where(guide:, section:).sum(:readers)

  # The sections this browser reported for the guide.
  def stored(guide) = page.evaluate_script("JSON.parse(localStorage.getItem('playground-guide-progress:#{guide}')) || []")

  def scroll_heading(id) = page.execute_script("document.getElementById(arguments[0]).scrollIntoView({ block: 'start' })", id)

  # The browser here never hides its tab, so the page is told it did.
  def hide_tab(hidden)
    page.execute_script(<<~JS)
      Object.defineProperty(document, "hidden", { value: #{hidden}, configurable: true })
      document.dispatchEvent(new Event("visibilitychange"))
    JS
  end

  # The journey counts of a guide: { [stage, minutes] => readers }, and the
  # sources they came with.
  def journey(guide) = GuideJourneyDay.where(guide:).group(:stage, :minutes).sum(:readers)
  def journey_sources(guide) = GuideJourneyDay.where(guide:).distinct.pluck(:first_source, :first_medium, :first_campaign, :last_source)

  # This browser's journey through a guide, as it keeps it.
  def kept_journey(guide) = page.evaluate_script("JSON.parse(localStorage.getItem('playground-guide-journey:#{guide}'))")

  # The reader does something, as a key press does.
  def nudge = page.execute_script("window.dispatchEvent(new KeyboardEvent('keydown'))")

  def wait_for(seconds = 10)
    deadline = Time.current + seconds
    sleep 0.2 until yield || Time.current > deadline
    assert yield, "waited #{seconds} seconds"
  end
end
