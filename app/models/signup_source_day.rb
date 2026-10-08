# How many new accounts came from each source (TrafficSource) on one US
# Eastern day, with nothing about who. The login form carries the browser's
# first and last touch through Hack Club's login in the OAuth round trip's
# own session (attribution.js, SessionsController). When that login makes a
# new account, the day's count for those sources goes up by one, and the
# touches go with the session. An account that already exists counts
# nothing, and no row names or links to an account.
class SignupSourceDay < ApplicationRecord
  def self.count!(first:, last:, day: Time.current.in_time_zone(ProgramWindow::ZONE).to_date)
    sources = TrafficSource.columns(self, day:, first:, last:)
    upsert({ day:, **sources, signups: 1 }, unique_by: :index_signup_source_days_uniquely,
                                             on_duplicate: Arel.sql("signups = signup_source_days.signups + 1"))
  end
end
