# One person on Stardance's playground mission active on one US Eastern day
# (StardanceActivity), for the admin stats' list of who was active. handle is
# their Stardance display name, which is also their profile's address.
class StardanceActivePerson < ApplicationRecord
  def slack_url = "https://hackclub.slack.com/team/#{ERB::Util.url_encode(slack_id)}"
  def stardance_url = handle.present? ? "https://stardance.hackclub.com/@#{ERB::Util.url_encode(handle)}" : nil
  def name = handle.presence || slack_id

  # The days' people by date, most time first. A day with none is absent.
  def self.per_day(days) = where(day: days).order(:day, seconds: :desc, slack_id: :asc).group_by(&:day)
end
