# Every hour, refreshes each participant's coding hours and pet totals
# (CodingHours), one participant at a time so Hackatime sees a steady
# trickle, least recently synced first. One participant's failure is logged
# and the run goes on. Once the program window has closed, only participants
# not yet synced after its end are refreshed, so the job then goes quiet.
#
# A Postgres advisory lock keeps two runs from overlapping, across processes
# too: a run that finds it taken does nothing. Postgres drops the lock if the
# process dies.
class CodingHoursJob < ApplicationJob
  queue_as :default

  LOCK = 4_263_781_023 # any fixed number; it names this job's advisory lock

  def self.due(window = ProgramWindow.current, now = Time.current)
    users = User.where.not(hackatime_access_token: nil)
    now >= window.ends_at ? users.where(coding_hours_synced_at: [ nil, ...window.ends_at ]) : users
  end

  def perform
    window = ProgramWindow.current
    return unless window.started?

    ActiveRecord::Base.with_connection do |db|
      next unless lock(db, "pg_try_advisory_lock")
      begin
        self.class.due(window).order(Arel.sql("coding_hours_synced_at ASC NULLS FIRST"), :id).ids.each { refresh(it, window) }
      ensure
        lock(db, "pg_advisory_unlock")
      end
    end
  end

  private

  # Jobs run with the query cache on, and a cached answer about the lock
  # would be wrong.
  def lock(db, function) = db.uncached { db.select_value("SELECT #{function}(#{LOCK})") }

  def refresh(id, window)
    user = User.find_by(id:)
    CodingHours.refresh(user, window:) if user
  rescue => e
    Rails.logger.error("coding hours refresh crashed for user #{id}: #{e.class}: #{e.message}")
  end
end
