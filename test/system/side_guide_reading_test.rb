require "application_system_test_case"

# A browser reading Stardance's or the clubs' guide counts its own reading
# time for the day, only while the tab shows, and once the time passes the
# threshold it tells the server once that day. The threshold is two seconds
# here, in place of twenty minutes.
class SideGuideReadingTest < ApplicationSystemTestCase
  KEY = "playground-guide-reading".freeze

  setup do
    @threshold = SideGuide.reading_seconds
    # The report sends the page's CSRF token, which only renders with this on.
    ActionController::Base.allow_forgery_protection = true
  end

  teardown do
    SideGuide.reading_seconds = @threshold
    ActionController::Base.allow_forgery_protection = false
  end

  test "past the threshold the browser reports one reader, once a day, however long it reads on" do
    SideGuide.reading_seconds = 2
    visit "/clubs"
    wait_for { GuideReaderDay.sum(:readers) == 1 }
    today = Time.current.in_time_zone(ProgramWindow::ZONE).to_date
    assert_equal [ [ today, "clubs", 1 ] ], GuideReaderDay.pluck(:day, :guide, :readers)

    # Another step, another guide, a reload, and more time add no reader.
    click_on "Build the scene", match: :first
    assert_current_path "/clubs/scene"
    visit "/stardance/move"
    sleep 1.5
    visit "/stardance/move"
    sleep 1.5
    assert_equal 1, GuideReaderDay.sum(:readers)
    stored = page.evaluate_script("JSON.parse(localStorage.getItem('#{KEY}'))")
    assert_equal [ today.iso8601, true ], [ stored["day"], stored["sent"] ]
    assert_operator stored["seconds"].values.sum, :>=, 2
  end

  test "a hidden tab adds no time, and the time shown goes on from where it was" do
    SideGuide.reading_seconds = 600
    visit "/stardance"
    assert_selector ".hub-outline"
    sleep 1
    set_hidden(true)
    hidden_at = stored_seconds
    assert_operator hidden_at, :>=, 0.8
    sleep 1.5
    set_hidden(false)
    sleep 1
    set_hidden(true)
    # About a second more, for the second while it showed, and none for the
    # second and a half while it hid.
    assert_in_delta hidden_at + 1, stored_seconds, 0.4
    assert_equal 0, GuideReaderDay.count
  end

  private

  def stored_seconds = page.evaluate_script("JSON.parse(localStorage.getItem('#{KEY}')).seconds.stardance")

  # The browser here never hides its tab, so the page is told it did.
  def set_hidden(hidden)
    page.execute_script(<<~JS)
      Object.defineProperty(document, "hidden", { value: #{hidden}, configurable: true })
      document.dispatchEvent(new Event("visibilitychange"))
    JS
  end

  def wait_for(seconds = 10)
    deadline = Time.current + seconds
    sleep 0.2 until yield || Time.current > deadline
    assert yield, "waited #{seconds} seconds"
  end
end
