require "test_helper"

# The top bar on every page but the landing: the logo, home, and two tabs,
# the guide and my pets, with the open one marked. The account and then
# help stand on the right. The sponsor and the requirements are elsewhere:
# the landing shows both, and the guide's ship step links the requirements.
class NewSiteTopbarTest < ActionDispatch::IntegrationTest
  include NewSiteTests
  HELP = "https://hackclub.slack.com/archives/C0ASBTMS82H".freeze

  test "the guide tab is open on the guide, my pets on every page of the pets, and neither elsewhere" do
    user = log_in("participant")
    rock = user.projects.create!(name: "rock")
    { guide_path => [ "guide", "page" ], projects_path => [ "my pets", "page" ],
      ship_project_path(rock) => [ "my pets", "true" ], delete_project_path(rock) => [ "my pets", "true" ], edit_project_path(rock) => [ "my pets", "true" ],
      checks_project_path(rock) => [ "my pets", "true" ], new_project_path => [ "my pets", "true" ],
      requirements_path => nil }.each do |path, (tab, current)|
      get path
      assert_response :success, path
      assert_select ".topbar .topbar-tabs a.topbar-tab", 2, path
      assert_select ".topbar a.topbar-tab[href=?]", guide_path, "guide"
      assert_select ".topbar a.topbar-tab[href=?]", projects_path, "my pets"
      if tab
        assert_select ".topbar a.topbar-tab[aria-current]", 1, path
        assert_select ".topbar a.topbar-tab[aria-current=?]", current, tab, path
      else
        assert_select ".topbar a.topbar-tab[aria-current]", 0, path
      end
    end
  end

  test "the logo goes home, sign out and then help stand on the right, and the sponsor and requirements are gone" do
    log_in("participant")
    get guide_path
    assert_equal [ "sign out", "help in #playground" ], css_select(".topbar-links a, .topbar-links button").map { it.text.strip }
    assert_select ".topbar a.topbar-home[href=?] img[alt=playground]", root_path
    assert_select ".topbar .topbar-links a[href=?][target=_blank]", HELP, "help in #playground"
    assert_select ".topbar .topbar-links form[action=?] button", logout_path, "sign out"
    assert_select ".topbar a[href=?]", admin_root_path, 0
    assert_select ".topbar a[href=?]", requirements_path, 0
    assert_no_match(/sponsored by/, css_select(".topbar").text)
  end

  test "an admin also gets a link to the admin" do
    log_in("admin")
    get guide_path
    assert_select ".topbar .topbar-links a.topbar-admin[href=?]", admin_root_path, "admin"
    assert_equal [ "admin", "sign out", "help in #playground" ], css_select(".topbar-links a, .topbar-links button").map { it.text.strip }
  end

  test "signed out, both tabs show, and my pets and sign in go to the login" do
    get guide_path
    assert_select ".topbar a.topbar-tab[aria-current=page][href=?]", guide_path, "guide"
    assert_select ".topbar a.topbar-tab:not([aria-current])[href=?]", login_path, "my pets"
    assert_select ".topbar .topbar-links a[href=?]", login_path, "sign in"
    assert_equal [ "sign in", "help in #playground" ], css_select(".topbar-links a").map { it.text.strip }
    assert_select ".topbar .topbar-links a[href=?]", HELP
    assert_select ".topbar button", 0

    get requirements_path
    assert_select ".topbar a.topbar-tab", 2
    assert_select ".topbar a.topbar-tab[aria-current]", 0
  end

  test "the landing has no top bar" do
    get root_path
    assert_select ".topbar", 0
  end

  # Turbo loads a page in full when its tracked links differ from the last
  # page's, so a visit between the new site and the desktop site's layouts,
  # such as the admin, never keeps one site's stylesheet on the other.
  test "the new site's layout reloads the page when a stylesheet changes, and the admin's layout tracks none" do
    log_in("admin")
    get guide_path
    assert_select "link[rel=stylesheet][href*='/playground-'][data-turbo-track=reload]", 1
    assert_select "link[rel=stylesheet][href*='/new_site-'][data-turbo-track=reload]", 1
    get admin_root_path
    assert_response :success
    assert_select "link[rel=stylesheet][href*='/playground-']", 1
    assert_select "link[rel=stylesheet][data-turbo-track]", 0
    assert_select "link[href*='/new_site-']", 0
  end
end
