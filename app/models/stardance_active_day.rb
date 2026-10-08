# How many people on Stardance's playground mission were active on one US
# Eastern day, counted by StardanceActivity: active, with enough Hackatime
# time on their playground projects, and unknown, whose time Hackatime would
# not show, as their stats are private. People active here that day are left out, so nobody counts
# twice. The table holds nothing about who.
class StardanceActiveDay < ApplicationRecord
  # The day's counts and who was active (StardanceActivity::Count), in one
  # transaction, replacing what the day held. The time comes from the app,
  # not the database, so it is the time the job saw (StardanceActivityJob.due).
  def self.record!(day, count)
    now = Time.current
    transaction do
      upsert({ day:, active: count.active, unknown: count.unknown, listed: true, created_at: now, updated_at: now },
             unique_by: :day, update_only: %i[active unknown listed updated_at], record_timestamps: false)
      StardanceActivePerson.where(day:).delete_all
      rows = count.people.map { |person, seconds| { day:, slack_id: person.slack_id, handle: person.handle, seconds:, created_at: now, updated_at: now } }
      StardanceActivePerson.insert_all(rows, record_timestamps: false) if rows.any?
    end
  end

  # The days' rows by date. A day not yet counted is absent.
  def self.per_day(days) = where(day: days).index_by(&:day)
end
