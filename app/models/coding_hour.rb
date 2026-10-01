# The seconds one participant coded in one hour, on the Hackatime projects
# that count for them. hour is the UTC start of the hour. Only time inside
# the program window is kept, and an hour with no time has no row.
# CodingHours fills the table; CodingHoursJob runs it every hour.
#
# The read methods below are for the admin statistics. Each is one SQL query,
# and each works on any scope, such as CodingHour.where(user: users).per_day.
# Days and hours of the day are US Eastern (ProgramWindow::ZONE), with
# daylight saving applied in SQL. Eastern offsets are whole hours, so each UTC
# hour falls in exactly one Eastern hour.
class CodingHour < ApplicationRecord
  belongs_to :user

  # The Eastern wall-clock time an hour starts at, in SQL. hour is stored as
  # UTC in a column without a zone.
  EASTERN = "((coding_hours.hour AT TIME ZONE 'UTC') AT TIME ZONE '#{ProgramWindow::ZONE}')".freeze

  scope :in_window, ->(window = ProgramWindow.current) { where(hour: window.starts_at.utc.beginning_of_hour...window.ends_at) }

  # One entry per Eastern day of the window, oldest first, days with no time
  # included: [{ date: Date, seconds: Integer, people: Integer }]. people
  # counts the participants with any time that day.
  def self.per_day(window = ProgramWindow.current)
    day = Arel.sql("#{EASTERN}::date")
    found = in_window(window).group(day).pluck(day, Arel.sql("SUM(seconds)"), Arel.sql("COUNT(DISTINCT user_id)"))
                             .to_h { |date, seconds, people| [ date, { seconds:, people: } ] }
    first = window.starts_at.in_time_zone(ProgramWindow::ZONE).to_date
    last = (window.ends_at - 1).in_time_zone(ProgramWindow::ZONE).to_date
    (first..last).map { |date| { date:, **found.fetch(date, { seconds: 0, people: 0 }) } }
  end

  # Seconds by Eastern weekday and hour of the day, over the whole window:
  # grid[wday][hour], with wday 0 for Sunday as in Date#wday and hour 0 to
  # 23. Zeros included. The window holds some weekdays more often than
  # others, and those hold more time.
  def self.hour_of_day_grid(window = ProgramWindow.current)
    wday = Arel.sql("EXTRACT(DOW FROM #{EASTERN})::int")
    hour = Arel.sql("EXTRACT(HOUR FROM #{EASTERN})::int")
    grid = Array.new(7) { Array.new(24, 0) }
    in_window(window).group(wday, hour).pluck(wday, hour, Arel.sql("SUM(seconds)")).each { |d, h, seconds| grid[d][h] = seconds }
    grid
  end

  # Each participant's first and last hour with time in the window:
  # { user_id => { first_hour: Time, last_hour: Time } }, each the UTC start
  # of the hour. For "time to first code" and "went quiet". Participants who
  # never coded are absent.
  def self.first_and_last_hours(window = ProgramWindow.current)
    in_window(window).group(:user_id).pluck(:user_id, Arel.sql("MIN(hour)"), Arel.sql("MAX(hour)"))
                     .to_h { |user_id, first, last| [ user_id, { first_hour: first, last_hour: last } ] }
  end

  # Seconds in the 7 days before now and in the 7 days before those:
  # { last_7_days: Integer, previous_7_days: Integer }. An hour counts in the
  # week its start falls in.
  def self.last_two_weeks(now = Time.current)
    cut = now - 7.days
    recent, before = where(hour: (cut - 7.days)..now).pick(
      Arel.sql(sanitize_sql([ "COALESCE(SUM(seconds) FILTER (WHERE hour >= ?), 0)", cut ])),
      Arel.sql(sanitize_sql([ "COALESCE(SUM(seconds) FILTER (WHERE hour < ?), 0)", cut ]))
    )
    { last_7_days: recent, previous_7_days: before }
  end
end
