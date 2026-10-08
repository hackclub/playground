require "test_helper"

# Visitors get the new site. Signed in, the user's flag (NewSite) decides:
# without it, every address answers as the desktop site does, and the new
# site's own addresses do not exist. With it, the new site shows, and the
# desktop site's pages send the user to theirs. A participant cannot set the flag. An
# admin can, from the person's page, and the person's history says who did.
class NewSiteGateTest < ActionDispatch::IntegrationTest
  MARKS = [ "new-site", "new_site-", "topbar", "home-window", "pet-window" ].freeze

  setup { @pet = User.create!(hca_id: "ident!gate-owner").projects.create!(name: "rock") }

  test "signed out, visitors get the new site and its public guide steps" do
    assert NewSite.for_visitors
    [ root_path, guide_path, requirements_path, login_path, *GuidePage.all.map { guide_page_path(it) } ].each do |path|
      get path
      assert_response :ok, path
      assert_select "body.new-site", 1, path
      assert_select "#welcome", 0, path
    end
    get guide_check_path
    assert_response :ok

    [ [ :get, guide_side_path ], [ :get, guide_ship_path ], [ :post, guide_link_path ],
      [ :patch, active_pet_path ], [ :get, ship_project_path(@pet) ], [ :get, delete_project_path(@pet) ] ].each do |verb, path|
      send(verb, path)
      assert_redirected_to login_path, "#{verb} #{path} still requires login"
    end
  end

  test "a participant without the flag gets the desktop site, and the new site's addresses do not exist" do
    user = log_in("participant")
    pet = user.projects.create!(name: "rock")
    new_only_requests(pet).each do |verb, path|
      send(verb, path)
      assert_response :not_found, "#{verb} #{path}"
    end
    [ root_path, root_path(open: "goal"), dashboard_path, guide_path, guide_path(step: "move"), requirements_path, project_path(pet),
      edit_project_path(pet), checks_project_path(pet), checks_project_path(pet, from: "guide"), trash_project_path(pet), new_project_path ].each do |path|
      get path
      assert_response :ok, path
      assert_desktop_site path
    end
    get projects_path
    assert_redirected_to dashboard_path
    get edit_project_path(pet)
    assert_select "form.button_to[action=?] button", project_path(pet), "delete pet"

    # A save, a delete, and a new pet go where the desktop site sends them,
    # whatever the request says, and set no active pet.
    patch project_path(pet), params: { checks: 1, from: "guide", project: { description: "a rock" } }
    assert_redirected_to checks_project_path(pet)
    post projects_path, params: { project: { name: "pebble" } }
    assert_redirected_to project_path(user.projects.find_by!(name: "pebble"))
    assert_nil cookies[:active_pet]
    delete project_path(pet)
    assert_redirected_to dashboard_path
  end

  test "with the legacy visitor setting, every page shows the desktop site to a visitor and to a participant without the flag" do
    NewSite.for_visitors = false
    user = User.create!(hca_id: "ident!gate-sweep")
    pet = user.projects.create!(name: "rock")
    paths = Rails.application.routes.routes.select { it.verb == "GET" && it.defaults[:controller] }
                 .map { it.path.spec.to_s.delete_suffix("(.:format)") }
                 .reject { it.start_with?("/rails/", "/admin", "/dev/", "/assets", "/cable", "/up") }
                 .map { it.gsub(":id", pet.id.to_s).gsub(":step", "move").gsub(":provider", "hack_club").gsub(":guide", "stardance").gsub(":block", "particles").delete("()") }.uniq
    # Stardance's and the clubs' guides (SideGuide), and the building blocks'
    # pages from them, are open to everyone.
    side_guides = paths.select { it.start_with?("/stardance") }
    assert_equal [ "/stardance/blocks/particles", "/stardance/move" ], side_guides.sort
    paths -= side_guides
    assert_operator paths.size, :>, 15
    [ nil, user ].each do |who|
      sign_in_as(who) if who
      cookies.delete(SideGuide::COOKIE.to_s)
      # Twice, so a page that changes on its first visit, as the Hackatime
      # step after a login does, has settled.
      bodies = 2.times.map do
        paths.to_h do |path|
          get path
          assert_desktop_site "#{who ? "participant" : "visitor"} #{path}"
          [ path, page_as_served ]
        end
      end.last

      # Every one shows the side guide, with no account, and no flag.
      SideGuide.all.each do |guide|
        get side_guide_path(guide, "move")
        assert_select "body.new-site.side-guide .hub-outline", 1
        assert_select ".topbar-tabs, #pick-step", 0
      end

      # Having opened one, every page of the desktop site is the same to the
      # byte, but / for a visitor, which goes back to the guide.
      paths.each do |path|
        get path
        if path == "/" && !who
          assert_redirected_to side_guide_path("clubs")
        else
          assert_equal bodies[path], page_as_served, "#{who ? "participant" : "visitor"} #{path} after a side guide"
        end
      end
    end
  ensure
    NewSite.for_visitors = true
  end

  test "a user with the flag gets the new site, and the desktop site's pages send them to theirs" do
    user = log_in("participant")
    user.update!(new_site: true)
    pet = user.projects.create!(name: "rock")

    get root_path
    assert_select "body.new-site .home-window", 4
    assert_select "link[rel=stylesheet][href*='/new_site-'][data-turbo-track=reload]"
    get root_path(open: "goal")
    assert_redirected_to guide_path
    get dashboard_path
    assert_redirected_to guide_path
    get project_path(pet)
    assert_redirected_to projects_path(anchor: "pet-#{pet.id}")
    get trash_project_path(pet)
    assert_redirected_to delete_project_path(pet)

    [ guide_path, guide_page_path("move"), projects_path, edit_project_path(pet), ship_project_path(pet), delete_project_path(pet),
      new_project_path, requirements_path ].each do |path|
      get path
      assert_response :ok, path
      assert_select "body.new-site .topbar", 1, path
    end

    # A message on the way to the dashboard, which is the guide now, stays.
    get new_redemption_path(goal_key: "shirt")
    assert_redirected_to dashboard_path
    follow_redirect!
    assert_redirected_to guide_path
    follow_redirect!
    assert_select ".flash.alert", /approved hours/

    post projects_path, params: { project: { name: "pebble" } }
    pebble = user.projects.find_by!(name: "pebble")
    assert_redirected_to projects_path(anchor: "pet-#{pebble.id}")
    assert cookies[:active_pet].present?
  end

  test "an expired login falls back to the visitor's new site without account access" do
    user = log_in("participant")
    user.update!(new_site: true)
    get guide_page_path("move")
    assert_response :ok
    user.increment!(:session_version)
    get guide_page_path("move")
    assert_response :ok
    assert_select "body.new-site"
    get projects_path
    assert_redirected_to login_path
  end

  test "a participant cannot turn the new site on" do
    user = log_in("participant")
    pet = user.projects.create!(name: "rock")
    patch project_path(pet), params: { project: { name: "rock", new_site: "1" }, user: { new_site: "1" }, new_site: "1" }
    patch project_path(pet), params: { project: { name: "rock" }, new_site: "1" }, as: :json
    patch trash_path, params: { icons: [ "rock" ], new_site: "1", user: { new_site: "1" } }
    get root_path(new_site: "1")
    get guide_path(new_site: true)
    get dev_login_path(as: "participant", new_site: "1")
    patch new_site_admin_person_path(user), params: { on: "1" }
    assert_response :not_found
    assert_not user.reload.new_site?

    # Nor can a user with the admin column whose email is not an organizer's.
    user.update!(admin: true)
    with_admin_emails("organizer@example.com") do
      patch new_site_admin_person_path(user), params: { on: "1" }
      assert_response :not_found
    end
    assert_not user.reload.new_site?
    get guide_page_path("move")
    assert_response :not_found
  end

  test "an admin turns the new site on and off from the person's page, and the history says who" do
    participant = User.create!(hca_id: "ident!gate-participant", email: "p@example.com")
    admin = log_in("admin")
    get root_path
    assert_desktop_site "an admin without the flag"

    get admin_person_path(participant)
    assert_select ".new-site-flag", /new site: off/ do
      assert_select "form[action=?] input[name=on][value='1']", new_site_admin_person_path(participant)
      assert_select "button", "turn the new site on"
    end

    patch new_site_admin_person_path(participant), params: { on: "1" }
    assert_redirected_to admin_person_path(participant)
    assert participant.reload.new_site?
    event = AuditEvent.where(subject: participant).sole
    assert_equal [ "new_site.on", admin ], [ event.action, event.actor ]
    follow_redirect!
    assert_select ".new-site-flag", /new site: on/
    assert_select ".new-site-flag button", "turn it off"
    assert_select ".events li", /#{Regexp.escape(admin.reload.display_name)} · new_site\.on/

    patch new_site_admin_person_path(participant), params: { on: "0" }
    assert_not participant.reload.new_site?
    assert_equal %w[new_site.on new_site.off], AuditEvent.where(subject: participant).order(:id).pluck(:action)
    assert_not admin.reload.new_site?, "the admin's own flag stays as it was"
  end

  test "the flag takes effect on the user's next request, either way" do
    user = log_in("participant")
    get guide_path
    assert_desktop_site "before"
    user.update!(new_site: true)
    get guide_path
    assert_select "body.new-site"
    user.update!(new_site: false)
    get guide_path
    assert_desktop_site "after"
  end

  private

  # The new site's own addresses, unavailable to signed-in users without the flag.
  def new_only_requests(pet)
    GuidePage.all.map { [ :get, guide_page_path(it) ] } +
      [ [ :get, guide_check_path ], [ :get, guide_side_path ], [ :get, guide_ship_path ], [ :post, guide_link_path ],
        [ :patch, active_pet_path ], [ :get, "/projects/#{pet.id}/ship" ], [ :get, delete_project_path(pet) ] ]
  end

  # What a request served, to compare: a page's HTML, or a not found's
  # status, since its debug page names the test's line.
  def page_as_served = response.status == 404 ? 404 : [ response.status, without_tokens(response.body) ]

  # A page's HTML without its CSRF tokens, which change on every request,
  # and without a flash message, which the request before it left.
  def without_tokens(body)
    body.gsub(/(name="csrf-token" content=")[^"]+/, '\\1').gsub(/(name="authenticity_token" value=")[^"]+/, '\\1')
        .gsub(%r{<p class="flash \w+">[^<]*</p>}, "")
  end

  def assert_desktop_site(message)
    MARKS.each { assert_not_includes response.body, it, message }
  end

  def sign_in_as(user)
    user.update!(hca_id: "ident!dev-participant") unless user.hca_id == "ident!dev-participant"
    get dev_login_path(as: "participant")
  end

  def with_admin_emails(list)
    before = ENV["ADMIN_EMAILS"]
    ENV["ADMIN_EMAILS"] = list
    yield
  ensure
    ENV["ADMIN_EMAILS"] = before
  end
end
