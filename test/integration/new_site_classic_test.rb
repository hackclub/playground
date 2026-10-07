require "test_helper"

# A user with the new site on (NewSite) can switch one browser back to the
# old desktop, from the end of the new site's footer or its landing's FAQ,
# after a question. A signed cookie keeps that browser on the old desktop,
# where an icon switches back. The flag stays as it is. Nobody else sees the
# link, the icon, or the switch's address, and a stray cookie changes
# nothing for them.
class NewSiteClassicTest < ActionDispatch::IntegrationTest
  MARKS = [ "new-site", "new_site-", "topbar", "home-window", "pet-window", "back-to-new-site", "classic" ].freeze

  setup do
    @user = log_in("participant")
    @user.update!(new_site: true)
  end

  test "every page of the new site ends its footer with the old desktop, which asks first" do
    pet = @user.projects.create!(name: "rock")
    [ root_path, guide_path, guide_page_path("move"), projects_path, edit_project_path(pet), requirements_path ].each do |path|
      get path
      assert_select ".footbar p:first-child a:last-child.footbar-classic[href=?][aria-haspopup=dialog]", classic_path, "the old desktop →", path
      assert_select ".footbar a.footbar-classic[data-controller=classic-switch][data-action='classic-switch#open']", 1, path
      assert_select "dialog#classic-dialog[aria-labelledby=classic-dialog-title]", 1, path
    end
    assert_select "#classic-dialog" do
      assert_select ".pet-titlebar h2#classic-dialog-title", "the old desktop"
      assert_select ".pet-titlebar form[method=dialog] button.classic-x[aria-label=close]", "X"
      assert_select "p", "switch to the old desktop? you can switch back anytime"
      assert_select "form[action=?][method=post] button.btn.primary", classic_path, "switch"
      assert_select "form[method=dialog] button.btn[autofocus]", "stay here"
    end

    # Without scripts the link goes to a page that asks the same.
    get classic_path
    assert_response :ok
    assert_select "body.new-site .page-window h2", "the old desktop"
    assert_select ".page-window p", "switch to the old desktop? you can switch back anytime"
    assert_select ".page-window form[action=?][method=post] button", classic_path, "switch"
    assert_select ".page-window a.btn[href=?]", root_path, "stay here"
  end

  test "switching keeps this browser on the old desktop, with an icon back, and the flag stays on" do
    post classic_path
    assert_redirected_to root_path
    set_cookie = Array(response.headers["Set-Cookie"]).join("\n")
    assert_match(/classic=.+; .*expires=/i, set_cookie)
    assert_match(/httponly/i, set_cookie)
    assert_match(/samesite=lax/i, set_cookie)
    assert @user.reload.new_site?

    get root_path
    assert_select "#welcome"
    assert_select "body.new-site", 0
    assert_select "form#back-to-new-site[action=?][method=post]", classic_path do
      assert_select "input[name=_method][value=delete]"
      assert_select "button.back-to-new-site img[src='/apple-touch-icon.png'][alt='']"
      assert_select "button.back-to-new-site span", "new playground"
    end
    get guide_path
    assert_select "h2#guide-overview", "Guide overview"
    get dashboard_path
    assert_response :ok
    get guide_page_path("move")
    assert_response :not_found
    get classic_path
    assert_redirected_to root_path

    delete classic_path
    assert_redirected_to root_path
    get root_path
    assert_select "body.new-site .home-window", 4
    assert_select "#back-to-new-site", 0
  end

  test "the icon back shows only with the flag and the cookie" do
    post classic_path
    get root_path
    assert_select "#back-to-new-site", 1

    @user.update!(new_site: false)
    get root_path
    assert_select "#welcome"
    assert_select "#back-to-new-site", 0

    delete logout_path
    get root_path
    assert_select "#welcome"
    assert_select "#back-to-new-site", 0
  end

  test "with the flag and the cookie, every page is the desktop site's, with the icon back on the desktop only" do
    post classic_path
    pet = @user.projects.create!(name: "rock")
    pages(pet, side_guides: false).each do |path|
      get path
      body = response.body.gsub(/<form id="back-to-new-site".*?<\/form>/m, "").gsub(%r{<link[^>]*back_to_new_site[^>]*>}, "")
      (MARKS - [ "classic" ]).each { assert_not_includes body, it, path }
      assert_equal path == "/", response.body.include?("back-to-new-site"), path
    end
  end

  test "a participant without the flag, and a visitor, with a stray cookie see exactly what they would without it" do
    post classic_path
    stray = cookies["classic"]
    assert stray.present?
    @user.update!(new_site: false)
    pet = @user.projects.create!(name: "rock")

    [ :participant, :visitor ].each do |who|
      delete logout_path if who == :visitor
      pages(pet).each do |path|
        # A first visit uses up any one-time state, such as the login's
        # Hackatime step, so the two visits compared find the same.
        get path
        cookies["classic"] = stray
        get path
        with = seen
        cookies.delete("classic")
        get path
        assert_equal seen, with, "#{who} #{path}"
        MARKS.each { assert_not_includes response.body, it, "#{who} #{path}" } unless response.status == 404 || side_guide?(path)
      end
    end
  end

  test "only a user with the flag can reach the switch, and the switch never sets the flag" do
    delete logout_path
    [ [ :get, classic_path ], [ :post, classic_path ], [ :delete, classic_path ] ].each do |verb, path|
      send(verb, path)
      assert_response :not_found, "visitor #{verb}"
    end
    other = log_in("unverified")
    [ [ :get, classic_path ], [ :post, classic_path ], [ :delete, classic_path ] ].each do |verb, path|
      send(verb, path)
      assert_response :not_found, "unflagged #{verb}"
    end
    assert_nil cookies["classic"]
    assert_not other.reload.new_site?
  end

  test "the new landing's FAQ says where the desktop went, only to an account made before the new site's launch" do
    # The day before the launch, in Eastern time.
    @user.update_columns(created_at: ActiveSupport::TimeZone[ProgramWindow::ZONE].local(2026, 10, 6, 12))
    get root_path
    assert_select ".home-faq details summary", "where did the desktop go?"
    assert_select ".home-faq details", text: /where did the desktop go\?/ do
      assert_select "p", /it's still here!/
      assert_select "a[href=?][data-controller=classic-switch]", classic_path, "open the old desktop →"
    end
    assert_select ".home-faq details:last-child summary", "i have more questions :("

    stub_const(NewSite, :LAUNCHED_ON, Date.new(2026, 10, 6)) do
      get root_path
      assert_select ".home-faq details summary", text: "where did the desktop go?", count: 0
    end

    delete logout_path
    NewSite.for_visitors = true
    get root_path
    assert_select ".home-faq"
    assert_select ".home-faq details summary", text: "where did the desktop go?", count: 0
    assert_select ".footbar-classic, #classic-dialog", 0
  ensure
    NewSite.for_visitors = false
  end

  private

  # A page as served. An error page's backtrace names the test's own lines,
  # so only its status counts.
  def seen = [ response.status, response.location, (response.body unless response.status == 404) ]

  # Every page the site serves, as in the gate's sweep. Stardance's and the
  # clubs' guides (SideGuide) show the new site's look to everyone.
  def pages(pet, side_guides: true)
    paths = Rails.application.routes.routes.select { it.verb == "GET" && it.defaults[:controller] }
                 .map { it.path.spec.to_s.delete_suffix("(.:format)") }
                 .reject { it.start_with?("/rails/", "/admin", "/dev/", "/assets", "/cable", "/up", "/auth/") }
                 .map { it.gsub(":id", pet.id.to_s).gsub(":step", "move").gsub(":provider", "hack_club").gsub(":guide", "stardance").delete("()") }.uniq
    side_guides ? paths : paths.reject { side_guide?(it) }
  end

  def side_guide?(path) = path.start_with?("/stardance", "/clubs")
end
