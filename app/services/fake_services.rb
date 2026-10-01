# In development, with no OAuth credentials, the app talks to these fakes so
# the whole flow can be driven by hand: log in, link Hackatime, submit,
# review, redeem. Never used in production.
module FakeServices
  def self.on?
    Rails.env.local? && ENV["REAL_SERVICES"] != "1"
  end
end
