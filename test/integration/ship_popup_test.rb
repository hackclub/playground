require "test_helper"

# ship.exe on the pet page. The page has the ship button and an empty popup.
# The list loads from checks, each fix saves through update with only its own
# field, and a ship that fresh data blocks comes back inside the popup.
class ShipPopupTest < ActionDispatch::IntegrationTest
  STREAM = { "Accept" => "text/vnd.turbo-stream.html, text/html, application/xhtml+xml" }.freeze
  READY = { description: "a rock that walks along your taskbar", code_url: "https://github.com/pet/rock",
            ship_message_url: "https://hackclub.slack.com/archives/C0C51NCK1DG/p1759012345678901", playable_url: "https://pet.itch.io/rock", hackatime_projects: [ "rock-pet" ],
            screenshots: [ { "id" => "shot", "key" => "shot.webp", "url" => "https://playground.hackclub-assets.com/shot.webp" } ] }.freeze

  setup do
    @user = log_in("participant")
    post dev_hackatime_path
    @project = @user.projects.create!(name: "rock")
  end

  test "the pet page has a ship button for ship.exe, and no checklist" do
    get project_path(@project)
    assert_select "a.btn[href='#{checks_project_path(@project)}'][aria-haspopup=dialog]", "ship"
    assert_select "dialog.popup.ship-popup[aria-labelledby=ship-popup-title]" do
      assert_select "h2.popup-title#ship-popup-title", "ship.exe"
      assert_select "button.popup-close[aria-label=close]", "X"
      assert_select "#ship-checks li[data-check]", 0
    end
    assert_select ".checks", 0
    assert_no_match "ready to ship?", response.body
  end

  test "the ship button names the pet for the desktop's window, and the popup drags by its title bar" do
    @project.update!(name: %(rock "the <b>rock</b>"))
    get project_path(@project)
    assert_select "[data-controller=ship-popup][data-ship-popup-project-value='#{@project.id}']" do |row|
      assert_equal %(rock "the <b>rock</b>"), row.first["data-ship-popup-name-value"]
    end
    assert_select "dialog.ship-popup[data-controller=popup-drag] .popup-head[data-popup-drag-target=head]"
    assert_select "b", 0, "the name is text"
  end

  test "in the desktop's ship window, the list tells the desktop what it saves, and has no way back to the pet page" do
    get checks_project_path(@project, window: 1)
    assert_select "section[data-controller=ship-window]", text: /ship rock/
    assert_select "a[href='#{project_path(@project)}']", 0

    get checks_project_path(@project)
    assert_select "a[href='#{project_path(@project)}']", "← rock"
  end

  test "the list shows only what blocks, each with only its own fix" do
    get checks_project_path(@project), headers: STREAM
    assert_response :ok
    assert_equal "text/vnd.turbo-stream.html", response.media_type
    assert_select "turbo-stream[action=replace][target=ship-checks][method=morph]"

    assert_select "#ship-checks li[data-check]", 6
    assert_select "#ship-checks li[data-check]", text: /your pet needs a name/, count: 0
    assert_fix "description", "textarea[name='project[description]']"
    assert_fix "hackatime_projects", "input[type=checkbox][name='project[hackatime_projects][]'][value='rock-pet']"
    assert_fix "code_url", "input[type=url][name='project[code_url]']"
    assert_fix "playable_url", "input[type=url][name='project[playable_url]']"
    assert_fix "screenshot", ".shots-grid .shot-cell.add"
    assert_fix "ship_message_url", "input[type=url][name='project[ship_message_url]']"
    # The README, the commits, and new hours wait for a repository and a
    # Hackatime project, though the ship waits for them too.
    assert_select "#ship-check-readme, #ship-check-commits, #ship-check-new_hours", 0
    # Each step's label says what to do. No line under it says it again.
    assert_no_match "→", response.body
    assert_select "#ship-checks button[disabled]", "ship"
  end

  test "a step that could be unclear has a tip that screen readers hear" do
    # An approved ship claimed every hour tracked so far.
    @project.update!(READY)
    TrackedTime.refresh(@project.reload, force: true)
    @project.ships.create!(user: @user, claimed_seconds: @project.reload.tracked_seconds, state: "approved",
                           created_at: ProgramWindow.current.starts_at + 1.hour)
    get checks_project_path(@project)
    assert_select "#ship-check-new_hours" do
      assert_select "button.tip-mark[type=button][aria-label='more about this'][aria-describedby=ship-tip-new_hours]", "i"
      assert_select "#ship-tip-new_hours[role=tooltip][hidden]",
                    "you can only ship a pet if you've tracked hours with Hackatime or Lapse since your last ship. " \
                    "maybe connect another Hackatime project, or track some more hours?"
    end
  end

  test "a fix saves only its own field and comes back with its step ticked" do
    patch project_path(@project), params: { checks: 1, shown: %w[description code_url],
                                            project: { description: "a rock that walks along your taskbar" } }, headers: STREAM
    assert_response :ok
    assert_equal "text/vnd.turbo-stream.html", response.media_type
    assert_equal "a rock that walks along your taskbar", @project.reload.description
    assert_nil @project.code_url
    assert_select "#ship-check-description.ok .icon", "✓"
    assert_select "#ship-check-description textarea", text: "a rock that walks along your taskbar"
    assert_select "#ship-check-code_url.todo .icon", "!"
  end

  test "a short description is kept, and the step stays with its label only" do
    patch project_path(@project), params: { checks: 1, project: { description: "a small rock" } }, headers: STREAM
    assert_response :ok
    assert_equal "a small rock", @project.reload.description
    assert_select "#ship-check-description.todo", text: /\A\s*!\s+the description needs at least 20\s+characters\s/
    assert_no_match "yours is", response.body
  end

  test "invalid input comes back with its error and what was typed, and saves nothing" do
    patch project_path(@project), params: { checks: 1, project: { code_url: "not a url" } }, headers: STREAM
    assert_response :unprocessable_entity
    assert_nil @project.reload.code_url
    assert_select "#ship-check-code_url.todo" do
      assert_select "form[novalidate] input[name='project[code_url]'][value='not a url']"
      assert_select ".banner.alert", "Code url must be a full http(s) link"
    end
  end

  test "a Hackatime project another pet has is refused in the list too" do
    @user.projects.create!(name: "other", hackatime_projects: [ "frog-widget" ])
    patch project_path(@project), params: { checks: 1, project: { hackatime_projects: [ "", "frog-widget" ] } }, headers: STREAM
    assert_response :unprocessable_entity
    assert_empty @project.reload.hackatime_projects
    assert_select "#ship-check-hackatime_projects .banner.alert", /already linked to another pet: frog-widget/
    assert_select "#ship-check-hackatime_projects input[value='frog-widget']", 0, "a taken project is not offered"
  end

  test "without JavaScript, a fix saves and lands back on the list" do
    patch project_path(@project), params: { checks: 1, project: { playable_url: "https://pet.itch.io/rock" } }
    assert_redirected_to checks_project_path(@project)
    follow_redirect!
    assert_select "h2", "ship rock"
    assert_select "#ship-check-playable_url", 0
  end

  test "the ship message step takes only a message link from #playground-ships, and the list points to the requirements" do
    get checks_project_path(@project), headers: STREAM
    assert_select "#ship-checks a[href='#{requirements_path}']", "submission requirements"
    assert_select "#ship-check-ship_message_url", /link your ship message in #playground-ships/

    [ "https://hackclub.slack.com/archives/C0ASBTMS82H/p1759012345678901", "https://example.com/archives/C0C51NCK1DG/p1", "not a link" ].each do |bad|
      patch project_path(@project), params: { checks: 1, project: { ship_message_url: bad } }, headers: STREAM
      assert_response :unprocessable_entity
      assert_nil @project.reload.ship_message_url
      assert_select "#ship-check-ship_message_url .banner.alert", /message in #playground-ships/
    end

    good = "https://hackclub.slack.com/archives/C0C51NCK1DG/p1759012345678901?thread_ts=1759012000.000100&cid=C0C51NCK1DG"
    patch project_path(@project), params: { checks: 1, shown: [ "ship_message_url" ], project: { ship_message_url: good } }, headers: STREAM
    assert_response :ok
    assert_equal good, @project.reload.ship_message_url
    assert_select "#ship-check-ship_message_url.ok"
  end

  test "once nothing blocks, the list offers the ship, and shipping lands on the pet page" do
    @project.update!(READY)
    get checks_project_path(@project), headers: STREAM
    assert_select "#ship-checks li[data-check]", 0
    assert_select "#ship-checks form[action='#{ship_project_path(@project)}'] button", /\Aship \d+h \d+m\z/
    assert_select "#ship-checks [role=status]", "all set! everything checks out."

    post ship_project_path(@project), headers: STREAM
    assert_redirected_to project_path(@project)
    assert_equal "shipped! your hours are pending review.", flash[:notice]
    assert @project.ships.sole.pending?
  end

  test "a ship that fresh data blocks shows why inside the popup, and on the list's page without JavaScript" do
    @project.update!(READY)
    # Another tab shipped part of this pet's hours after the popup opened.
    @project.ships.create!(user: @user, claimed_seconds: 60)

    post ship_project_path(@project), headers: STREAM
    assert_response :unprocessable_entity
    assert_equal "text/vnd.turbo-stream.html", response.media_type
    assert_select "#ship-checks .banner.alert", "not yet: your last ship needs its review first"
    assert_select "#ship-check-not_pending", text: /your last ship needs its review first/
    assert_select "#ship-checks button[disabled]", "ship"

    post ship_project_path(@project)
    assert_redirected_to checks_project_path(@project)
    assert_equal "not yet: your last ship needs its review first", flash[:alert]
    assert_equal 1, @project.ships.count
  end

  test "a warning is listed as a warning, as a condition, and does not stop the ship" do
    OfflineGithub.repo = OfflineGithub::REPO.with(commits: 1)
    @project.update!(READY)
    get checks_project_path(@project)
    assert_select "#ship-checks li[data-check]", 1
    assert_select "#ship-check-commits.warn", text: /\A\s*!\s+the repository should have more than one\s+commit\s+i/
    assert_no_match "a reviewer will look at this", response.body
    assert_select "#ship-checks form[action='#{ship_project_path(@project)}'] button", /\Aship /
  end

  test "a shipped link off itch.io warns to go where someone can experience the pet, and still ships with the warning kept" do
    @project.update!(READY.merge(playable_url: "https://pet.example.com"))
    get checks_project_path(@project)
    assert_select "#ship-check-playable_host.warn", text: /the shipped link needs to go to a page where someone can experience your pet/
    assert_select "#ship-check-playable_host .fix", 0
    assert_select "#ship-checks form[action='#{ship_project_path(@project)}'] button", /\Aship /

    post ship_project_path(@project)
    assert_redirected_to project_path(@project)
    assert_includes @project.ships.sole.snapshot["warnings"], "the shipped link needs to go to a page where someone can experience your pet"
  end

  test "a pet in review lists the wait, and offers no ship" do
    @project.update!(READY)
    @project.ships.create!(user: @user, claimed_seconds: 60)
    get checks_project_path(@project)
    assert_select "#ship-check-not_pending", text: /your last ship needs its review first/
    assert_select "form[action='#{ship_project_path(@project)}']", 0
    assert_select "#ship-checks button[disabled]", "ship"
  end

  test "a ship warns when Lapse time is over 30% of the claimed hours" do
    @project.update!(READY)
    with_lapse_share(0.31) { post ship_project_path(@project) }
    assert_includes @project.ships.sole.snapshot["warnings"], "Lapse time is 31% of the claimed hours; art counts at most 30%"
  end

  test "a ship with Lapse time under 30% of the claimed hours has no art warning" do
    @project.update!(READY)
    with_lapse_share(0.29) { post ship_project_path(@project) }
    assert_empty @project.ships.sole.snapshot["warnings"].grep(/Lapse time/)
  end

  private

  # Lapses worth this share of whatever the ship claims. The shipper asks
  # after it saves the fresh Hackatime total, so a fresh read sees it.
  def with_lapse_share(share)
    original = LapseLinks.method(:for)
    id = @project.id
    LapseLinks.define_singleton_method(:for) do |_user, _projects|
      duration = share * Project.find(id).unshipped_seconds
      LapseLinks::Result.new(lapses: [ LapseLinks::Lapse.new(id: "lapse#{share}", title: "art", duration:, project: "rock-pet", url: "https://lapse.hackclub.com/timelapse/lapse#{share}") ], error: nil)
    end
    yield
  ensure
    LapseLinks.define_singleton_method(:for, original)
  end

  def assert_fix(key, field)
    assert_select "#ship-check-#{key}.todo" do
      assert_select field
      assert_select ".fix", text: /with edit/, count: 0
    end
  end
end
