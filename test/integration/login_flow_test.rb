require "test_helper"

# Login is Hack Club Auth, then Hackatime, then the desktop with ship.exe open.
# Both OAuth apps are placeholders: OmniAuth's test mode stands in for a
# provider that says yes, and the state and deny cases run the real strategy,
# which checks the state before it would call the network.
class LoginFlowTest < ActionDispatch::IntegrationTest
  setup do
    OmniAuth.config.test_mode = true
    @omniauth_logger, OmniAuth.config.logger = OmniAuth.config.logger, Rails.logger
    ENV["REAL_SERVICES"] = "1"
  end

  teardown do
    OmniAuth.config.test_mode = false
    OmniAuth.config.logger = @omniauth_logger
    OmniAuth.config.mock_auth.delete(:hack_club)
    OmniAuth.config.mock_auth.delete(:hackatime)
    ENV.delete("REAL_SERVICES")
    ENV.delete("ADMIN_EMAILS")
    ActionController::Base.allow_forgery_protection = false
  end

  test "a login with a Slack id queues the add to #playground, and one without does not" do
    assert_no_enqueued_jobs(only: SlackInviteJob) { hca_login("ident!no-slack") }

    user = nil
    assert_enqueued_with(job: SlackInviteJob) { hca_login("ident!slacker", slack_id: "U0SLACKER") }
    user = User.find_by!(hca_id: "ident!slacker")
    assert_enqueued_with(job: SlackInviteJob, args: [ user.id ])

    user.update!(slack_invited_at: Time.current)
    assert_no_enqueued_jobs(only: SlackInviteJob) { hca_login("ident!slacker", slack_id: "U0SLACKER") }
  end

  test "a new participant goes from Hack Club Auth to Hackatime to the desktop" do
    hca_login("ident!new")
    assert_redirected_to hackatime_step_path
    follow_redirect!
    assert_response :success
    assert_select "form[action='/auth/hackatime'][method=post][target=_top][data-controller=auto-submit]" do
      assert_select "button[data-turbo=false]", "continue to Hackatime"
    end
    # The step shows as login.exe. Hack Club is done and ticks over, and
    # Hackatime is the step to do now.
    assert_select "section.login" do
      assert_select ".login-title[aria-hidden=true]", "login.exe"
      assert_select "ol.login-steps[aria-label='login steps'] li.login-step", 2
      assert_select "li.login-step.done.just-done:not([aria-current]) .step-label", "Hack Club, done"
      assert_select "li.login-step.current[aria-current=step] .step-label", "Hackatime"
    end

    OmniAuth.config.mock_auth[:hackatime] = OmniAuth::AuthHash.new(provider: "hackatime", credentials: { token: "hka_new" })
    post "/auth/hackatime"
    follow_redirect!
    assert_redirected_to root_path(open: "goal")
    assert_equal "hka_new", User.find_by!(hca_id: "ident!new").hackatime_access_token

    get dashboard_path
    assert_select "h2", text: "hackatime", count: 0
    assert_no_match "isn't linked yet", response.body
    assert_no_match "never run both at once", response.body
  end

  # The button shows only with a Hack Club Auth app. Each look sets whether
  # there is one, whatever the machine's credentials hold.
  test "the login shows its two steps with Hack Club to do now, and its button posts in the top window" do
    Rails.application.credentials.define_singleton_method(:dig) { |*keys| keys == %i[hack_club client_id] ? nil : options.dig(*keys) }
    get login_path
    assert_select "section.panel.login" do
      assert_select ".login-title[aria-hidden=true]", "login.exe"
      assert_select "ol.login-steps[aria-label='login steps'] li.login-step", 2
      assert_select "li.login-step.current[aria-current=step] .step-label", "Hack Club"
      assert_select "li.login-step:not(.current):not(.done):not([aria-current]) .step-label", "Hackatime"
      assert_select "li.done, li.just-done", 0
      assert_select "p.muted", "then you'll link Hackatime, which tracks your coding time."
      assert_select "form", 0
    end

    Rails.application.credentials.define_singleton_method(:dig) { |*keys| keys == %i[hack_club client_id] ? "test-client" : options.dig(*keys) }
    get login_path
    assert_select ".login form.button_to[action='/auth/hack_club'][method=post][target=_top] button.btn.primary[data-turbo=false]", "log in with Hack Club"
  ensure
    Rails.application.credentials.singleton_class.remove_method(:dig) if Rails.application.credentials.singleton_methods.include?(:dig)
  end

  test "a returning participant with a Hackatime token goes straight to the desktop, again after logging out" do
    User.create!(hca_id: "ident!back", hackatime_access_token: "hka_old")
    hca_login("ident!back")
    assert_redirected_to root_path(open: "goal")

    delete logout_path
    hca_login("ident!back")
    assert_redirected_to root_path(open: "goal")
    assert_equal "hka_old", User.find_by!(hca_id: "ident!back").hackatime_access_token
  end

  test "after log out, a copy of the old session cookie signs no one in, and a new login does" do
    User.create!(hca_id: "ident!back", hackatime_access_token: "hka_old")
    hca_login("ident!back")
    get dashboard_path
    assert_select "button", text: "log out"
    old = cookies["_website_session"]

    delete logout_path
    # A response that left before the log out sets the old cookie again.
    cookies["_website_session"] = old
    get dashboard_path
    assert_redirected_to login_path
    # A request for data gets a 401, and leaves no "log in first" for the next page.
    get projects_path, headers: { "Accept" => "application/json" }
    assert_response :unauthorized
    get login_path
    assert_select ".login"
    assert_select ".flash", count: 0

    hca_login("ident!back")
    get dashboard_path
    assert_select "button", text: "log out"
  end

  test "an unverified participant and an admin get the Hackatime step too, and an ineligible account does not" do
    hca_login("ident!unverified", status: "needs_submission", eligible: false)
    assert_redirected_to hackatime_step_path

    reset!
    ENV["ADMIN_EMAILS"] = "orga@example.com"
    hca_login("ident!orga", email: "orga@example.com")
    assert_redirected_to hackatime_step_path
    assert User.find_by!(hca_id: "ident!orga").admin?

    reset!
    hca_login("ident!nope", status: "ineligible", eligible: false)
    assert_redirected_to login_path
    assert_equal "Hack Club says this account can't join programs like playground.", flash[:alert]
    get hackatime_step_path
    assert_redirected_to login_path, "not logged in"
  end

  test "an organizer whose email leaves ADMIN_EMAILS stops being an admin, on the next request and at login" do
    ENV["ADMIN_EMAILS"] = "orga@example.com,,"
    hca_login("ident!orga", email: "orga@example.com")
    get admin_root_path
    assert_response :success

    ENV["ADMIN_EMAILS"] = "someone-else@example.com"
    get admin_root_path
    assert_response :not_found

    reset!
    hca_login("ident!orga", email: "orga@example.com")
    assert_not User.find_by!(hca_id: "ident!orga").admin?
  end

  test "a blank entry in ADMIN_EMAILS makes nobody an admin" do
    ENV["ADMIN_EMAILS"] = ",orga@example.com"
    hca_login("ident!noemail", email: nil)
    assert_not User.find_by!(hca_id: "ident!noemail").admin?
  end

  test "a callback for no known provider goes to the login with a message" do
    OmniAuth.config.test_mode = false
    get "/auth/nobody/callback"
    assert_redirected_to login_path
    assert_equal "login did not finish: unknown error", flash[:alert]
  end

  test "declining Hackatime keeps the participant logged in, with a button to try again" do
    hca_login("ident!decline")
    OmniAuth.config.test_mode = false
    post "/auth/hackatime"
    authorize = URI(response.location)
    query = Rack::Utils.parse_query(authorize.query)
    assert_equal "https://hackatime.hackclub.com/oauth/authorize", "#{authorize.scheme}://#{authorize.host}#{authorize.path}"
    assert_equal [ "test-client", "http://www.example.com/auth/hackatime/callback", "code", "profile read" ],
                 query.values_at("client_id", "redirect_uri", "response_type", "scope")

    get "/auth/hackatime/callback", params: { error: "access_denied", state: query.fetch("state") }
    assert_redirected_to root_path(open: "goal")
    assert_equal "Hackatime did not link (access_denied). your coding time counts once it's linked.", flash[:alert]
    assert_nil User.find_by!(hca_id: "ident!decline").hackatime_access_token

    get dashboard_path
    assert_select ".topline", /hi/
    assert_select ".banner", /Hackatime, Hack Club's free coding time tracker, isn't linked yet/ do
      assert_select "form[action='/auth/hackatime'][method=post][target=_top] button[data-turbo=false]", "link Hackatime"
    end
  end

  test "a Hackatime callback with the wrong state links nothing" do
    hca_login("ident!forged")
    OmniAuth.config.test_mode = false
    post "/auth/hackatime"
    get "/auth/hackatime/callback", params: { code: "someone-elses-code", state: "not-the-state" }
    assert_redirected_to root_path(open: "goal")
    assert_match "(csrf_detected)", flash[:alert]
    assert_nil User.find_by!(hca_id: "ident!forged").hackatime_access_token
  end

  test "both OAuth request phases need a POST with the page's CSRF token" do
    ActionController::Base.allow_forgery_protection = true
    get login_path
    login_token = css_select("meta[name=csrf-token]").first["content"]
    post "/auth/hack_club"
    assert_redirected_to login_path
    assert_equal "login did not finish: unknown error", flash[:alert]
    hca_login("ident!csrf", authenticity_token: login_token)
    follow_redirect!

    token = css_select("form[action='/auth/hackatime'] input[name=authenticity_token]").first["value"]
    post "/auth/hackatime"
    assert_redirected_to root_path(open: "goal")
    assert_equal "Hackatime did not link. your coding time counts once it's linked.", flash[:alert]
    get "/auth/hackatime"
    assert_response :not_found
    post "/auth/hackatime", params: { authenticity_token: token }
    assert_redirected_to "http://www.example.com/auth/hackatime/callback"
  end

  test "the Hackatime step starts only straight after a login" do
    hca_login("ident!once")
    get hackatime_step_path
    assert_response :success
    get hackatime_step_path
    assert_redirected_to root_path(open: "goal"), "a reload or a link does not start Hackatime again"
  end

  test "an OmniAuth failure message is shown only as an error key" do
    get auth_failure_path(message: "call 555 0100 for a prize", strategy: "hack_club")
    assert_equal "login did not finish: unknown error", flash[:alert]
    get auth_failure_path(message: "invalid_credentials", strategy: "hack_club")
    assert_equal "login did not finish: invalid_credentials", flash[:alert]
  end

  private

  def hca_login(id, email: "#{id.delete_prefix("ident!")}@example.com", status: "verified", eligible: true, slack_id: nil, **params)
    identity = { id:, primary_email: email, first_name: "Sam", last_name: "Dev", verification_status: status, ysws_eligible: eligible || nil, slack_id: }
    OmniAuth.config.mock_auth[:hack_club] = OmniAuth::AuthHash.new(
      provider: "hack_club", uid: id, credentials: { token: "hca-#{id}", refresh_token: "hcr-#{id}" },
      extra: { raw_info: { identity: identity.compact } }
    )
    post "/auth/hack_club", params: params
    follow_redirect!
  end
end

# The same chain in development, with fake services.
class DevLoginFlowTest < ActionDispatch::IntegrationTest
  test "the dev login runs the same chain through fake Hackatime" do
    get dev_login_path(as: "participant")
    assert_redirected_to hackatime_step_path
    follow_redirect!
    assert_select "form[action='#{dev_hackatime_path}'][target=_top][data-controller=auto-submit] button", "continue to Hackatime (dev)"
    post dev_hackatime_path
    assert_redirected_to root_path(open: "goal")
    assert_equal "fake", User.find_by!(hca_id: "ident!dev-participant").hackatime_access_token

    get dev_login_path(as: "participant")
    assert_redirected_to root_path(open: "goal")
  end

  test "deny=1 acts out a declined consent, and the dashboard offers the fake link again" do
    get dev_login_path(as: "unverified", deny: 1)
    assert_redirected_to hackatime_step_path(deny: 1)
    follow_redirect!
    assert_select "form[action='#{dev_hackatime_path(deny: 1)}']"
    post dev_hackatime_path(deny: 1)
    follow_redirect!
    assert_redirected_to root_path(open: "goal")
    assert_match "Hackatime did not link (access_denied)", flash[:alert]
    assert_nil User.find_by!(hca_id: "ident!dev-unverified").hackatime_access_token

    get dashboard_path
    assert_select ".banner form[action='#{dev_hackatime_path}'][target=_top] button", "link Hackatime (dev)"
  end

  # The desktop shows the login's page as login.exe. Signed out, the dashboard
  # and every page behind the login send the visitor there, and signed in,
  # the login goes on to the desktop with ship.exe open.
  test "the login is a page of its own, where a signed-out page goes and which a login skips" do
    get dashboard_path
    assert_redirected_to login_path
    follow_redirect!
    assert_select ".flash", 0
    assert_select "section.login .login-title", "login.exe"
    assert_select ".dev-logins a[href=?][target=_top]", dev_login_path(as: "participant"), text: "participant"

    get new_project_path
    assert_redirected_to login_path
    follow_redirect!
    assert_select "body > .flash.alert", "log in first"
    assert_select "section.login"

    log_in("participant")
    get login_path
    assert_redirected_to root_path(open: "goal")
    get dashboard_path
    assert_select "h2", "your meter"
    assert_select ".login", 0
  end

  test "the admin shortcut skips the chain" do
    get dev_login_path(as: "admin", admin: 1)
    assert_redirected_to admin_root_path
  end

  test "a banned Hackatime account shows its banner once linked" do
    user = log_in("red")
    user.update!(hackatime_trust_level: "red")
    get dashboard_path
    assert_select ".banner", /Hackatime, Hack Club's free coding time tracker, isn't linked yet/
    assert_no_match "Hackatime has banned", response.body

    post dev_hackatime_path
    get dashboard_path
    assert_select ".banner.alert", /Hackatime has banned this account/
    assert_select ".banner", text: /Hackatime, Hack Club's free coding time tracker, isn't linked yet/, count: 0
  end
end
