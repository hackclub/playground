require "test_helper"

# The admin statistics' reads of coding hours: Eastern days and hours of the
# day, grouped in SQL, with daylight saving.
class CodingHourTest < ActiveSupport::TestCase
  WINDOW = ProgramWindow.load({ starts_at: "2026-09-25 17:00", ends_at: "2026-10-12 09:00" })
  # The clocks go back at 2am EDT on Sunday 2026-11-01, 06:00 UTC.
  AUTUMN = ProgramWindow.load({ starts_at: "2026-10-31 12:00", ends_at: "2026-11-02 12:00" })

  def et(text) = ActiveSupport::TimeZone[ProgramWindow::ZONE].parse(text)

  setup do
    ProgramWindow.current = WINDOW
    @ada, @bo = %w[ada bo].map { User.create!(hca_id: "ident!coding-#{it}") }
  end

  def code(user, hour, seconds) = CodingHour.create!(user:, hour:, seconds:)

  test "per_day has every Eastern day of the window, days with no time as zeros" do
    code(@ada, et("2026-09-25 16:00"), 3600) # before the window
    code(@ada, et("2026-09-25 17:00"), 1800)
    code(@bo, et("2026-09-25 23:00"), 600)
    code(@ada, et("2026-09-26 21:00"), 900) # already the 27th in UTC
    code(@ada, et("2026-10-12 08:00"), 300)
    code(@bo, et("2026-10-12 09:00"), 3600) # after the window

    days = CodingHour.per_day
    assert_equal 18, days.size
    assert_equal [ Date.new(2026, 9, 25), Date.new(2026, 10, 12) ], [ days.first[:date], days.last[:date] ]
    assert_equal({ date: Date.new(2026, 9, 25), seconds: 2400, people: 2 }, days[0])
    assert_equal({ date: Date.new(2026, 9, 26), seconds: 900, people: 1 }, days[1])
    assert_equal({ date: Date.new(2026, 9, 27), seconds: 0, people: 0 }, days[2])
    assert_equal({ date: Date.new(2026, 10, 12), seconds: 300, people: 1 }, days[17])
    assert_equal 3600, days.sum { it[:seconds] }
    assert_equal [ 300 ], CodingHour.where(user: @ada).per_day.last.values_at(:seconds), "works on a scope"
  end

  test "per_day and the grid follow the clocks going back" do
    code(@ada, Time.utc(2026, 11, 1, 3), 100)  # Sat 31 Oct, 23:00 EDT
    code(@ada, Time.utc(2026, 11, 1, 4), 200)  # Sun 1 Nov, 00:00 EDT
    code(@ada, Time.utc(2026, 11, 1, 5), 300)  # 01:00 EDT
    code(@bo, Time.utc(2026, 11, 1, 6), 400)   # 01:00 EST, the same hour again
    code(@ada, Time.utc(2026, 11, 2, 4), 500)  # Sun 1 Nov, 23:00 EST
    code(@ada, Time.utc(2026, 11, 2, 5), 600)  # Mon 2 Nov, 00:00 EST

    assert_equal [ [ Date.new(2026, 10, 31), 100, 1 ], [ Date.new(2026, 11, 1), 1400, 2 ], [ Date.new(2026, 11, 2), 600, 1 ] ],
                 CodingHour.per_day(AUTUMN).map { it.values_at(:date, :seconds, :people) }
    grid = CodingHour.hour_of_day_grid(AUTUMN)
    assert_equal 100, grid[6][23]
    assert_equal [ 200, 700 ], grid[0][0..1], "both 1am hours of the 1st land on 1am"
    assert_equal 500, grid[0][23]
    assert_equal 600, grid[1][0]
    assert_equal 2100, grid.flatten.sum
  end

  test "hour_of_day_grid is 7 weekdays by 24 Eastern hours, zeros included" do
    code(@ada, et("2026-09-26 21:00"), 900)  # a Saturday
    code(@bo, et("2026-10-03 21:00"), 600)   # the next Saturday
    code(@bo, et("2026-09-27 09:00"), 1200)  # a Sunday
    grid = CodingHour.hour_of_day_grid
    assert_equal [ 7, [ 24 ] ], [ grid.size, grid.map(&:size).uniq ]
    assert_equal 1500, grid[6][21]
    assert_equal 1200, grid[0][9]
    assert_equal 2700, grid.flatten.sum
  end

  test "first_and_last_hours gives each participant's first and last hour in the window" do
    code(@ada, et("2026-09-25 16:00"), 3600) # before the window
    code(@ada, et("2026-09-26 10:00"), 60)
    code(@ada, et("2026-10-01 22:00"), 60)
    code(@ada, et("2026-09-28 13:00"), 60)
    code(@bo, et("2026-09-30 08:00"), 60)
    assert_equal({ @ada.id => { first_hour: et("2026-09-26 10:00"), last_hour: et("2026-10-01 22:00") },
                   @bo.id => { first_hour: et("2026-09-30 08:00"), last_hour: et("2026-09-30 08:00") } }, CodingHour.first_and_last_hours)
    assert_empty CodingHour.where(user: User.create!(hca_id: "ident!coding-none")).first_and_last_hours
  end

  test "last_two_weeks splits the 14 days before now into the last 7 and the 7 before" do
    now = et("2026-10-10 12:30")
    assert_equal({ last_7_days: 0, previous_7_days: 0 }, CodingHour.last_two_weeks(now))
    code(@ada, et("2026-10-10 12:00"), 1000) # the hour now is in
    code(@bo, et("2026-10-03 13:00"), 200)   # starts 6 days 23 and a half hours before
    code(@ada, et("2026-10-03 12:00"), 30)   # starts 7 days 30 minutes before
    code(@ada, et("2026-09-26 13:00"), 4)    # starts 13 days 23 and a half hours before
    code(@ada, et("2026-09-26 12:00"), 3600) # starts 14 days 30 minutes before
    assert_equal({ last_7_days: 1200, previous_7_days: 34 }, CodingHour.last_two_weeks(now))
    assert_equal({ last_7_days: 200, previous_7_days: 0 }, CodingHour.where(user: @bo).last_two_weeks(now))
  end

  test "the table refuses more than an hour's seconds and hours that aren't whole" do
    assert_raises(ActiveRecord::CheckViolation) { code(@ada, et("2026-09-26 10:00"), 3601) }
    assert_raises(ActiveRecord::CheckViolation) { code(@ada, et("2026-09-26 10:30"), 60) }
    assert_raises(ActiveRecord::CheckViolation) { code(@ada, et("2026-09-26 10:00"), -1) }
  end
end
