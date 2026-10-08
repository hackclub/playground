# How many people on Stardance's playground mission were active on one US
# Eastern day, counted by StardanceActivity: active, with enough Hackatime
# time on their playground projects, and unknown, whose time Hackatime would
# not show, as their stats are private. People active here that day are left out, so nobody counts
# twice. The table holds nothing about who.
class StardanceActiveDay < ApplicationRecord
  # The time comes from the app, not the database, so it is the time the
  # job saw (StardanceActivityJob.due).
  def self.record!(day, active:, unknown:)
    now = Time.current
    upsert({ day:, active:, unknown:, created_at: now, updated_at: now },
           unique_by: :day, update_only: %i[active unknown updated_at], record_timestamps: false)
  end

  # The days' rows by date. A day not yet counted is absent.
  def self.per_day(days) = where(day: days).index_by(&:day)
end
