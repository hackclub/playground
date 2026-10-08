require "test_helper"

# Where new accounts come from: the login form puts the browser's first and
# last touch on the login's address, OmniAuth keeps them for the round trip,
# and a login that makes a new account adds one to the day's count for them.
# Nothing goes on the account, an account that exists counts nothing, and
# the touches leave no trace in the session or the log.
class SignupSourcesTest < ActionDispatch::IntegrationTest
  NOW = Time.utc(2026, 10, 8, 15)
  SOURCES = { first_source: "clubs", first_medium: "email", first_campaign: "launch", last_source: "slack", last_medium: "referral", last_campaign: "" }.freeze

  setup do
    travel_to NOW
    OmniAuth.config.test_mode = true
    @omniauth_logger, OmniAuth.config.logger = OmniAuth.config.logger, Rails.logger
    ENV["REAL_SERVICES"] = "1"
  end

  teardown do
    OmniAuth.config.test_mode = false
    OmniAuth.config.logger = @omniauth_logger
    OmniAuth.config.mock_auth.delete(:hack_club)
    ENV.delete("REAL_SERVICES")
  end

  test "a new account adds one to its day's count for where it came from, and nothing to the account" do
    login("ident!new", SOURCES)
    user = User.find_by!(hca_id: "ident!new")
    assert_equal [ [ Date.new(2026, 10, 8), "clubs", "email", "launch", "slack", "referral", "", 1 ] ],
                 SignupSourceDay.pluck(:day, *SOURCES.keys, :signups)
    # Where the display name came from is the only source a user has.
    assert_equal [ "display_name_source" ], User.column_names.grep(/source|medium|campaign|touch|utm|referr/)
    assert_not user.attributes.values.any? { it.to_s.in?(%w[clubs launch slack]) }
    assert_not SignupSourceDay.column_names.any? { it.match?(/user|account|email|ip/) }

    login("ident!other", SOURCES)
    assert_equal [ 2 ], SignupSourceDay.pluck(:signups)
  end

  test "an account that exists, an ineligible one, or a dev login counts nothing" do
    login("ident!new", SOURCES)
    login("ident!new", SOURCES.merge(first_source: "github"))
    login("ident!nope", SOURCES, status: "ineligible")
    assert_nil User.find_by(hca_id: "ident!nope")
    ENV.delete("REAL_SERVICES")
    get dev_login_path(as: "newbie")
    assert User.exists?(hca_id: "ident!dev-newbie")
    assert_equal [ 1 ], SignupSourceDay.pluck(:signups)
  end

  test "a login with no touches counts as unknown, and junk is other" do
    login("ident!bare")
    login("ident!junk", { first_source: "<script>", first_medium: "x" * 50, last_source: "Hack Club Site" })
    assert_equal [ [ "other", "other", "hack club site" ], [ "unknown", "", "unknown" ] ],
                 SignupSourceDay.order(:first_source).pluck(:first_source, :first_medium, :last_source)
  end

  test "the touches stay out of the session after the login, and out of the log" do
    login("ident!new", SOURCES)
    assert_nil session["omniauth.params"]
    assert_not session.to_h.values.any? { it.to_s.include?("launch") }
    filter = ActiveSupport::ParameterFilter.new(Rails.application.config.filter_parameters)
    assert_equal SOURCES.keys.to_h { [ it.to_s, "[FILTERED]" ] }, filter.filter(SOURCES.stringify_keys)
  end

  private

  def login(id, touches = {}, status: "verified")
    identity = { id:, primary_email: "#{id.delete_prefix("ident!")}@example.com", first_name: "Sam", last_name: "Dev",
                 verification_status: status, ysws_eligible: status == "verified" || nil }
    OmniAuth.config.mock_auth[:hack_club] = OmniAuth::AuthHash.new(
      provider: "hack_club", uid: id, credentials: { token: "hca-#{id}" }, extra: { raw_info: { identity: identity.compact } }
    )
    post [ "/auth/hack_club", touches.to_query.presence ].compact.join("?")
    follow_redirect!
  end
end
