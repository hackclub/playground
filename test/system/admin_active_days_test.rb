require "application_system_test_case"

# The stats page's chart of people active each day, with a minute or more
# in Hackatime. The page opens with today pressed and today's people
# listed. Clicking another day's bar, or moving to it with the arrow keys,
# presses it and lists who was active on it.
class AdminActiveDaysTest < ApplicationSystemTestCase
  INK = "rgb(43, 58, 77)".freeze

  setup do
    ProgramWindow.current = ProgramWindow.new(starts_at: 3.days.ago, ends_at: 10.days.from_now)
    midnight = Time.current.in_time_zone(ProgramWindow::ZONE).beginning_of_day
    @first = 3.days.ago.in_time_zone(ProgramWindow::ZONE).to_date
    @today = midnight.to_date
    @yesterday = @today - 1
    @ann, @bob, cal = %w[ann bob cal].map { User.create!(hca_id: "ident!days-#{it}", display_name: it, display_name_source: "generated") }
    CodingHour.create!(user: @ann, hour: midnight, seconds: 1800)
    CodingHour.create!(user: cal, hour: midnight, seconds: 30) # under a minute, so not active
    CodingHour.create!(user: @bob, hour: midnight - 12.hours, seconds: 3600)
    CodingHour.create!(user: @ann, hour: midnight - 11.hours, seconds: 600)
    visit dev_login_path(as: "admin", admin: 1)
    assert_selector ".adminnav"
    visit admin_stats_path
  end

  test "today is pressed, and clicking another day presses it and lists who was active on it" do
    assert_pressed @today
    assert_equal INK, page.evaluate_script("getComputedStyle(document.querySelector('.dau-day[aria-pressed=true] .day-label')).backgroundColor")
    within(".dau-list") do
      assert_text "today, #{@today.strftime("%A %B %-d")}: 1 person active"
      assert_equal %w[ann], all("td a").map(&:text)
    end

    find("button.dau-day[data-date='#{@yesterday.iso8601}']").click
    assert_pressed @yesterday
    assert_selector ".dau-list", count: 1
    within(".dau-list") do
      assert_text "#{@yesterday.strftime("%A %B %-d")}: 2 people active"
      assert_equal [ [ "bob", "coded 1h 0m" ], [ "ann", "coded 10m" ] ], all("tr").filter_map { |row| row.all("td").map(&:text).presence }
    end
    assert_equal INK, page.evaluate_script("getComputedStyle(document.querySelector('.dau-day[aria-pressed=true] .day-label')).backgroundColor")

    find("button.dau-day[data-date='#{@first.iso8601}']").click
    assert_pressed @first
    within(".dau-list") { assert_text "nobody was active on this day." }

    find("button.dau-day[data-date='#{@yesterday.iso8601}']").click
    within(".dau-list") { click_link "bob" }
    assert_current_path admin_person_path(@bob)
  end

  test "the arrow keys, Home, and End press the day they move to, and the pressed day alone takes Tab" do
    find("button.dau-day[aria-pressed=true]").send_keys(:left)
    assert_pressed @yesterday
    assert_equal @yesterday.iso8601, page.evaluate_script("document.activeElement.dataset.date")
    within(".dau-list") { assert_text "2 people active" }

    page.active_element.send_keys(:home)
    assert_pressed @first
    within(".dau-list") { assert_text "nobody was active on this day." }
    page.active_element.send_keys(:left)
    assert_pressed @first

    page.active_element.send_keys(:end)
    assert_pressed @today
    assert_equal @today.iso8601, page.evaluate_script("document.activeElement.dataset.date")
    assert_equal [ "-1", "-1", "-1", "0" ], all("button.dau-day").map { it["tabindex"] }
  end

  test "on a phone a long window scrolls the chart, not the page, and opens on today" do
    ProgramWindow.current = ProgramWindow.new(starts_at: 29.days.ago, ends_at: 10.days.from_now)
    resize_viewport_to(390, 844) do
      visit admin_stats_path
      assert_pressed @today
      assert_operator page.evaluate_script("document.documentElement.scrollWidth"), :<=, 390
      assert_equal 30, all("button.dau-day").size
      assert today_in_view?, "the chart opens scrolled to today"
      find("button.dau-day[aria-pressed=true]").send_keys(:home)
      assert_pressed ProgramWindow.current.starts_at.in_time_zone(ProgramWindow::ZONE).to_date
      assert_equal 0, page.evaluate_script("document.querySelector('.dau-scroll').scrollLeft")
      page.active_element.send_keys(:end)
      assert_pressed @today
      assert today_in_view?
    end
  end

  private

  # The pressed day is wholly inside the chart's scrolled view, which is
  # narrower than all the days. Scroll offsets are whole pixels, so the day
  # may sit a fraction of one past the edge.
  def today_in_view?
    page.evaluate_script(<<~JS)
      (() => {
        const box = document.querySelector(".dau-scroll").getBoundingClientRect()
        const day = document.querySelector(".dau-day[aria-pressed=true]").getBoundingClientRect()
        return document.querySelector(".dau-scroll").scrollWidth > box.width && day.left >= box.left - 1 && day.right <= box.right + 1
      })()
    JS
  end

  def assert_pressed(date)
    assert_selector "button.dau-day[aria-pressed=true]", count: 1
    assert_selector "button.dau-day[aria-pressed=true][tabindex='0'][data-date='#{date.iso8601}']"
    assert_selector ".dau-list", count: 1
    assert_selector ".dau-list#active-#{date.iso8601}"
  end
end
