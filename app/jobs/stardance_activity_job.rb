# Every hour, counts the people on Stardance's playground mission active
# today and yesterday (StardanceActivity), and stores the counts
# (StardanceActiveDay) and who they were (StardanceActivePerson). A day of
# the window with no count or no list of people yet, as on the first run,
# is counted too. One day's failure is logged and the run goes
# on. Once the window has closed, a day is counted once more after the close
# and then left alone, so the job goes quiet.
#
# Without a Stardance MCP token it does nothing. When the server rejects the
# token, the run stops with one line in the log.
#
# A Postgres advisory lock keeps two runs from overlapping, as in
# CodingHoursJob.
class StardanceActivityJob < ApplicationJob
  queue_as :default

  LOCK = 4_263_781_024 # any fixed number; it names this job's advisory lock

  # The Eastern days to count now, oldest first.
  def self.due(window = ProgramWindow.current, now = Time.current)
    zone = ProgramWindow::ZONE
    today = now.in_time_zone(zone).to_date
    days = (window.starts_at.in_time_zone(zone).to_date..[ (window.ends_at - 1).in_time_zone(zone).to_date, today ].min).to_a
    counted = StardanceActiveDay.where(day: days, listed: true).pluck(:day, :updated_at).to_h
    days.select do |day|
      next true unless counted.key?(day)
      day >= today - 1 && (now < window.ends_at || counted[day] < window.ends_at)
    end
  end

  def perform
    window = ProgramWindow.current
    return unless window.started? && StardanceMcp.configured?
    days = self.class.due(window)
    return if days.empty?

    ActiveRecord::Base.with_connection do |db|
      next unless lock(db, "pg_try_advisory_lock")
      begin
        people = StardanceActivity.people
        here = StardanceActivity.active_here(window)
        days.each { count(it, people, here.fetch(it, Set.new)) }
      ensure
        lock(db, "pg_advisory_unlock")
      end
    end
  rescue StardanceMcp::Rejected => e
    Rails.logger.error(e.message)
  end

  private

  # Jobs run with the query cache on, and a cached answer about the lock
  # would be wrong.
  def lock(db, function) = db.uncached { db.select_value("SELECT #{function}(#{LOCK})") }

  def count(day, people, here)
    StardanceActiveDay.record!(day, StardanceActivity.count(day, people, here:))
  rescue => e
    Rails.logger.error("Stardance activity count crashed for #{day}: #{e.class}")
  end
end
