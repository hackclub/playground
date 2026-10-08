# What the endpoints that browsers report anonymous counts to share
# (GuideReadersController, GuideSectionsController, GuideJourneysController):
# the US Eastern day, the day a report names, if it is a date, and the key
# their rate limit counts by. The key is a keyed hash of the address and the day, not the address
# itself, so no address is kept, even in the cache, and it changes daily.
module AnonymousCounting
  extend ActiveSupport::Concern

  private

  def today = Time.current.in_time_zone(ProgramWindow::ZONE).to_date

  # A report counts only for today or yesterday, so a reader just past
  # midnight still counts, and a made-up day does not.
  def asked_day
    day = Date.iso8601(params[:day].to_s)
    day if day.between?(today - 1, today)
  rescue Date::Error
    nil
  end

  # The day a journey began, which a browser reports as long as it reads
  # (GuideJourneyDay): any of the last COHORT_DAYS days, or tomorrow, for a
  # browser whose clock runs a little ahead at midnight.
  def journey_day
    day = Date.iso8601(params[:day].to_s)
    day if day.between?(today - GuideJourneyDay::COHORT_DAYS, today + 1)
  rescue Date::Error
    nil
  end

  def anonymous_key
    OpenSSL::HMAC.hexdigest("SHA256", Rails.application.secret_key_base, "#{today}:#{request.remote_ip}").first(16)
  end
end
