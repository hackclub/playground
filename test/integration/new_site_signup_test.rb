require "test_helper"

# An account made at signup starts on the new site (NewSite). An account that
# already exists keeps its flag at every login, and an admin can still turn a
# new account's flag off. Only accounts made before the launch day, in
# Eastern time, find where the desktop went in the new landing's FAQ.
class NewSiteSignupTest < ActionDispatch::IntegrationTest
  setup do
    OmniAuth.config.test_mode = true
    ENV["REAL_SERVICES"] = "1"
  end

  teardown do
    OmniAuth.config.test_mode = false
    OmniAuth.config.mock_auth.delete(:hack_club)
    OmniAuth.config.mock_auth.delete(:hackatime)
    ENV.delete("REAL_SERVICES")
  end

  test "a new account starts on the new site, and after Hackatime lands on the guide" do
    hca_login("ident!brand-new")
    user = User.find_by!(hca_id: "ident!brand-new")
    assert user.new_site?

    # The Hackatime step comes first, as for every first login, on the new site.
    assert_redirected_to hackatime_step_path
    follow_redirect!
    assert_select "body.new-site section.login li.login-step.current .step-label", "Hackatime"

    OmniAuth.config.mock_auth[:hackatime] = OmniAuth::AuthHash.new(provider: "hackatime", credentials: { token: "hka_new" })
    post "/auth/hackatime"
    follow_redirect!
    assert_redirected_to root_path(open: "goal")
    follow_redirect!
    assert_redirected_to guide_path
    follow_redirect!
    assert_select "body.new-site #guide h1", "Build a desktop pet in Godot"
    assert_select "#welcome", 0

    get root_path
    assert_select "body.new-site .home-window", 4
    assert_select ".home-faq details summary", text: "where did the desktop go?", count: 0
  end

  test "an account that exists keeps its flag at login, off or on" do
    User.create!(hca_id: "ident!before", hackatime_access_token: "hka_old")
    hca_login("ident!before")
    assert_not User.find_by!(hca_id: "ident!before").new_site?
    assert_redirected_to root_path(open: "goal")
    follow_redirect!
    assert_select "#welcome"
    assert_select "body.new-site", 0
    delete logout_path

    User.create!(hca_id: "ident!flagged", hackatime_access_token: "hka_old", new_site: true)
    hca_login("ident!flagged")
    assert User.find_by!(hca_id: "ident!flagged").new_site?
    follow_redirect!
    assert_redirected_to guide_path
  end

  test "an admin can turn a new account's flag off, and it stays off at the next login" do
    hca_login("ident!brand-new")
    user = User.find_by!(hca_id: "ident!brand-new")
    admin_session = open_session
    ENV.delete("REAL_SERVICES") # the development login runs only with fake services
    admin_session.get dev_login_path(as: "admin")
    ENV["REAL_SERVICES"] = "1"
    admin_session.patch new_site_admin_person_path(user), params: { on: "0" }
    assert_not user.reload.new_site?

    delete logout_path
    hca_login("ident!brand-new")
    assert_not user.reload.new_site?
  end

  test "an ineligible new account is still turned away, and no account is made" do
    hca_login("ident!nope", status: "ineligible", eligible: false)
    assert_redirected_to login_path
    assert_nil User.find_by(hca_id: "ident!nope")
  end

  test "the development login's accounts start without the new site, like the accounts from before it" do
    ENV.delete("REAL_SERVICES")
    get dev_login_path(as: "participant")
    assert_not User.find_by!(hca_id: "ident!dev-participant").new_site?
  end

  test "only an account made before the launch day, in Eastern time, finds where the desktop went" do
    zone = ActiveSupport::TimeZone[ProgramWindow::ZONE]
    launch = NewSite::LAUNCHED_ON
    {
      zone.local(launch.year, launch.month, launch.day) - 1.day => true,
      # Late in the evening before, in Eastern time, which is already the
      # launch day in UTC.
      zone.local(launch.year, launch.month, launch.day) - 30.minutes => true,
      zone.local(launch.year, launch.month, launch.day) => false,
      zone.local(launch.year, launch.month, launch.day) + 1.day => false
    }.each do |made, knew|
      user = User.create!(hca_id: "ident!made-#{made.to_i}", hackatime_access_token: "hka", new_site: true, created_at: made)
      hca_login(user.hca_id)
      get root_path
      assert_select ".home-faq details summary", { text: "where did the desktop go?", count: knew ? 1 : 0 }, made.iso8601
      delete logout_path
    end
  end

  private

  def hca_login(id, status: "verified", eligible: true)
    identity = { id:, primary_email: "#{id.delete_prefix("ident!")}@example.com", first_name: "Sam", last_name: "Dev",
                 verification_status: status, ysws_eligible: eligible || nil }
    OmniAuth.config.mock_auth[:hack_club] = OmniAuth::AuthHash.new(
      provider: "hack_club", uid: id, credentials: { token: "hca-#{id}", refresh_token: "hcr-#{id}" },
      extra: { raw_info: { identity: identity.compact } }
    )
    post "/auth/hack_club"
    follow_redirect!
  end
end
