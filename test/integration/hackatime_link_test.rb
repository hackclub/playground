require "test_helper"

# A participant whose Hackatime token no longer works: they revoked it, or
# Hackatime restricted the account. Hackatime answers 404 on stats and 401 on
# the project list (github.com/hackclub/hackatime, stats and authenticated API
# controllers). No page errors, the token is kept, and each page offers the
# link again. HttpJson.get answers for Hackatime; nothing reaches the network.
class HackatimeLinkTest < ActionDispatch::IntegrationTest
  setup do
    @user = log_in("participant")
    @user.update!(hackatime_access_token: "hka_revoked")
    @project = @user.projects.create!(name: "rock", description: "a rock that naps on your taskbar", hackatime_projects: [ "rock-pet" ])
    ENV["REAL_SERVICES"] = "1"
    @statuses = statuses = { "/api/v1/users/my/stats" => 404, "/api/v1/authenticated/projects" => 401 }
    HttpJson.singleton_class.alias_method(:real_get, :get)
    HttpJson.define_singleton_method(:get) do |url, **|
      uri = URI(url)
      raise "unexpected request to #{uri.host}" unless url.start_with?(Hackatime::SITE)
      raise HttpJson::Error.new("GET #{uri.host}#{uri.path} -> #{statuses.fetch(uri.path)}", status: statuses.fetch(uri.path))
    end
  end

  teardown do
    HttpJson.singleton_class.alias_method(:get, :real_get)
    ENV.delete("REAL_SERVICES")
    OmniAuth.config.test_mode = false
    OmniAuth.config.mock_auth.delete(:hackatime)
  end

  test "ship shows a blocker instead of crashing, and keeps the token" do
    [ 404, 401 ].each do |status|
      @statuses["/api/v1/users/my/stats"] = status
      post ship_project_path(@project)
      assert_redirected_to checks_project_path(@project)
      assert_equal "not yet: Hackatime can't see your account through this link. link it again below", flash[:alert]
      assert_empty @project.ships.reload
      assert_equal "hka_revoked", @user.reload.hackatime_access_token

      follow_redirect!
      assert_select ".checks li", text: /your Hackatime link needs to work/ do
        assert_select "button.tip-mark[aria-describedby=ship-tip-hackatime_link]"
        assert_select "#ship-tip-hackatime_link[role=tooltip]", /link it again to fix it/
        assert_select "form[action='/auth/hackatime'][method=post][target=_top] button[data-turbo=false]", "link it again"
      end
      assert_select "button[disabled]", "ship"
    end
  end

  test "the edit page says the same, with a relink button outside the pet form" do
    get edit_project_path(@project)
    assert_response :success
    assert_select "fieldset p.banner.alert", /Hackatime can't see your account through this link\./ do
      assert_select "button[form=hackatime-relink][data-turbo=false]:not([name])", "link it again"
    end
    assert_select "form#hackatime-relink[action='/auth/hackatime'][method=post][target=_top][data-turbo=false][hidden]"
    assert_select "form form", 0
    assert_no_match "could not load Hackatime", response.body
  end

  test "the dashboard still loads" do
    get dashboard_path
    assert_response :success
    assert_select ".banner", text: /isn't linked yet/, count: 0
  end

  test "a Hackatime outage still reads as could not load" do
    @statuses["/api/v1/authenticated/projects"] = 503
    get edit_project_path(@project)
    assert_select "fieldset p.banner.alert", /could not load Hackatime: .* 503/
    assert_select "#hackatime-relink", 0
  end

  test "linking again replaces the stored token" do
    OmniAuth.config.test_mode = true
    OmniAuth.config.mock_auth[:hackatime] = OmniAuth::AuthHash.new(provider: "hackatime", credentials: { token: "hka_fresh" })
    post "/auth/hackatime"
    follow_redirect!
    assert_redirected_to root_path(open: "goal")
    assert_equal "hka_fresh", @user.reload.hackatime_access_token
  end
end

# Where people pick Hackatime projects, the fieldset holds the projects alone,
# with no lines about Hackatime and Lapse above them.
class HackatimePickerCopyTest < ActionDispatch::IntegrationTest
  test "the Hackatime projects fieldset has no explainer above the projects" do
    user = log_in("participant")
    post dev_hackatime_path
    project = user.projects.create!(name: "rock")
    get edit_project_path(project)
    assert_response :success
    assert_select "fieldset legend", "Hackatime projects"
    [ "free coding time tracker", "timelapses", "never run both at once", "pick every project" ].each do |line|
      assert_no_match line, response.body
    end
    assert_select "fieldset a[href='https://lapse.hackclub.com']", count: 0
  end
end
