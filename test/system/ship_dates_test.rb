require "application_system_test_case"

# Ship dates show in the viewer's own format, on the day of the viewer's own
# time zone. The server sends the ISO date in a <time>, and the browser
# rewrites it, so the ISO date is what shows without scripts.
class ShipDatesTest < ApplicationSystemTestCase
  # Stored screenshots load from this app, so the browser can draw them.
  class LocalStore < MemoryScreenshotStore
    def url(key) = "#{Capybara.current_session.server.base_url}/icon.png?#{key}"
  end

  setup do
    log_in_as "participant"
    user = User.find_by!(hca_id: "ident!dev-participant")
    @project = user.projects.create!(name: "rock", description: "naps on your windows")
    # 21:00 on 23 September in Honolulu, and already the 24th in UTC
    @project.ships.create!(user: user, created_at: Time.utc(2026, 9, 24, 7))
    # 22:30 on 23 September in UTC, and already the 24th in Berlin and Tokyo
    @project.ships.create!(user: user, created_at: Time.utc(2026, 9, 23, 22, 30))
  end

  teardown do
    ActionController::Base.allow_forgery_protection = false
    cdp("Emulation.setScriptExecutionDisabled", value: false)
    cdp("Emulation.setLocaleOverride")
    cdp("Emulation.setTimezoneOverride", timezoneId: "")
  end

  test "each locale shows its own format, on the day of the viewer's time zone" do
    {
      [ "en-US", "Pacific/Honolulu" ] => [ "Sep 23, 2026", "Sep 23, 2026" ],
      [ "en-GB", "Europe/London" ] => [ "24 Sept 2026", "23 Sept 2026" ],
      [ "de-DE", "Europe/Berlin" ] => [ "24.09.2026", "24.09.2026" ],
      [ "ja-JP", "Asia/Tokyo" ] => [ "2026/09/24", "2026/09/24" ]
    }.each do |(locale, zone), dates|
      emulate(locale, zone)
      visit project_path(@project)
      assert_formatted dates, "#{locale} in #{zone}"
    end
  end

  test "without scripts, each date is the ISO date in UTC, in a time element" do
    cdp("Emulation.setScriptExecutionDisabled", value: true)
    visit project_path(@project)
    assert_selector ".ships time[datetime='2026-09-24T07:00:00Z']", exact_text: "2026-09-24"
    assert_selector ".ships time[datetime='2026-09-23T22:30:00Z']", exact_text: "2026-09-23"
    assert_equal "undefined", page.evaluate_script("typeof window.Stimulus"), "the page loaded with scripts off"
  end

  test "in the pet's own window, dates stay formatted after a Turbo visit and a return from edit" do
    ScreenshotStore.current = LocalStore.new
    # The upload sends the page's CSRF token, which only renders with this on.
    ActionController::Base.allow_forgery_protection = true
    shot = Tempfile.new([ "shot", ".png" ]).tap { it.binmode; it.write(image_bytes(1280, 720)); it.close }
    emulate("de-DE", "Europe/Berlin")
    visit root_path(open: "goal")

    within_frame(find(".ship-frame")) { click_link "rock" }
    within_frame(find("#window-pet-#{@project.id} iframe")) do
      assert_formatted [ "24.09.2026", "24.09.2026" ]
      page.execute_script("window.samePage = true")

      # Saving the edit form draws the pet page again, with new rows.
      page.execute_script("document.querySelectorAll('.ships time').forEach((t) => (t.dataset.old = ''))")
      click_link "edit"
      find("input[type=file]", visible: :hidden).set(shot.path)
      assert_text "uploaded ✓"
      click_button "save"
      assert_selector "img.shot"
      assert_no_text "your pet needs a screenshot"
      assert_no_selector ".ships time[data-old]"
      assert_formatted [ "24.09.2026", "24.09.2026" ]
      assert page.evaluate_script("window.samePage"), "edit and save were Turbo visits"
    end
  ensure
    shot&.unlink
  end

  private

  def cdp(command, **params) = page.driver.browser.execute_cdp(command, **params)

  def emulate(locale, zone)
    cdp("Emulation.setLocaleOverride", locale: locale)
    cdp("Emulation.setTimezoneOverride", timezoneId: zone)
  end

  # Waits until no date shows the ISO fallback, then compares every date.
  def assert_formatted(dates, message = nil)
    assert_no_selector ".ships time", text: /\A\d{4}-\d\d-\d\d\z/
    assert_equal dates, all(".ships time").map(&:text), message
  end
end
