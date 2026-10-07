require "test_helper"

# The NPS form on the desktop and at ship. The desktop gives nps.exe an icon
# for a participant the site asks, and opens it by itself when they are due.
# A ship needs an answer when there is none from the last 12 hours, and the
# server holds the ship until it has one.
class NpsTest < ActionDispatch::IntegrationTest
  STREAM = { "Accept" => "text/vnd.turbo-stream.html, text/html, application/xhtml+xml" }.freeze
  READY = { description: "a rock that walks along your taskbar", code_url: "https://github.com/pet/rock",
            ship_message_url: "https://hackclub.slack.com/archives/C0C51NCK1DG/p1759012345678901", playable_url: "https://pet.itch.io/rock", hackatime_projects: [ "rock-pet" ],
            screenshots: [ { "id" => "shot", "key" => "shot.webp", "url" => "https://playground.hackclub-assets.com/shot.webp" } ] }.freeze
  ANSWER = { score: "9", doing_well: "the guide's videos", improve: "more pet ideas", anything_else: "" }.freeze

  setup do
    NpsResponse.asking = true
  end

  test "a participant's desktop asks with no answer in the last 12 hours, once they have a minute of Hackatime time" do
    user = log_in("participant")
    get root_path
    assert_select "#apps[data-nps]", 1, "the icon, for a newcomer too"
    assert_select "#apps[data-nps-ask]", 0, "no time yet"
    CodingHour.create!(user:, hour: 2.days.ago.beginning_of_hour, seconds: 60)
    get root_path
    assert_select "#apps[data-nps][data-nps-ask]"

    post nps_path, params: { nps_response: ANSWER }
    get root_path
    assert_select "#apps[data-nps]"
    assert_select "#apps[data-nps-ask]", 0

    NpsResponse.where(user:).update_all(created_at: 12.hours.ago + 1.minute)
    get root_path
    assert_select "#apps[data-nps-ask]", 0, "11 hours 59 minutes ago"
    NpsResponse.where(user:).update_all(created_at: 12.hours.ago - 1.minute)
    get root_path
    assert_select "#apps[data-nps-ask]", 1, "12 hours 1 minute ago"
  end

  test "a visitor, an admin at work, and a banned participant get no nps.exe" do
    get root_path
    assert_select "#apps[data-nps]", 0
    log_in("admin")
    get root_path
    assert_select "#apps[data-nps]", 0
    get nps_path
    assert_redirected_to dashboard_path

    log_in("participant").update!(banned_at: Time.current)
    get root_path
    assert_select "#apps[data-nps]", 0
  end

  test "with the asking off, nps.exe has no icon and opens nowhere" do
    log_in("participant")
    NpsResponse.asking = false
    get root_path
    assert_select "#apps[data-nps]", 0
  end

  test "nps.exe's page asks the score from 0 to 10 and the three questions, and a sent answer leaves a fresh form" do
    user = log_in("participant")
    get nps_path
    assert_response :ok
    assert_select "section.nps[data-controller=nps-window]"
    assert_select "form#nps-form[action='#{nps_path}']" do
      assert_select "fieldset.nps-score legend", /how likely are you to recommend playground to a friend\?/
      assert_select "input[type=radio][name='nps_response[score]'][required]", 11
      assert_equal (0..10).map(&:to_s), css_select("input[type=radio]").map { it["value"] }
      assert_select ".nps-ends", "0 = not at all10 = very very likely"
      assert_select "label[for=nps_response_doing_well]", /what are we doing well\?/
      assert_select "textarea#nps_response_doing_well[required]"
      assert_select "label[for=nps_response_improve]", /what's something we can improve\?/
      assert_select "textarea#nps_response_improve[required]"
      assert_select "label[for=nps_response_anything_else]", /anything else you want to tell us\?\s+optional/
      assert_select "textarea#nps_response_anything_else:not([required])"
      assert_select "button[type=submit]", "submit"
      assert_select "a.btn[href='/'][data-action='nps-window#close']", "cancel"
    end
    assert_no_match(/reward|gold|prize/, response.body)

    post nps_path, params: { nps_response: ANSWER.merge(anything_else: "love it") }
    assert_redirected_to nps_path
    answer = NpsResponse.sole
    assert_equal [ user, 9, "the guide's videos", "more pet ideas", "love it", "daily", nil ],
                 [ answer.user, answer.score, answer.doing_well, answer.improve, answer.anything_else, answer.source, answer.project ]
    follow_redirect!
    assert_select "form#nps-form textarea", text: "", count: 3
    assert_select "input[type=radio][checked]", 0
    assert_no_match(/thanks/, response.body)
  end

  test "an answer missing a required part is not saved, and keeps what was typed" do
    log_in("participant")
    post nps_path, params: { nps_response: ANSWER.merge(improve: "  ") }
    assert_response :unprocessable_entity
    assert_empty NpsResponse.all
    assert_select ".banner.alert", "pick a number and fill in the * ones first."
    assert_select "input[type=radio][value='9'][checked]"
    assert_select "textarea#nps_response_doing_well", "the guide's videos"

    post nps_path, params: { nps_response: ANSWER.merge(score: "11") }
    assert_response :unprocessable_entity
    assert_empty NpsResponse.all
  end

  test "with no answer in the last 12 hours, the ship list has a step for one, last, which blocks the ship" do
    user, project = ready_to_ship
    assert_empty CodingHour.where(user:), "a newcomer, whom nps.exe does not ask by itself, still answers at ship"
    get checks_project_path(project), headers: STREAM
    assert_equal %w[nps], css_select("#ship-checks li[data-check]").map { it["data-check"] }
    assert_select "#ship-check-nps.todo" do
      assert_select ".icon", "!"
      assert_select ".label-end", /going/
      assert_select ".tip-text", "we ask every 12 hours. be honest!"
      assert_select "form.fix.nps-fix[action='#{nps_path}'][data-ship-checks-target=form][data-saves-when-sent]" do
        assert_select "input[type=hidden][name=checks][value='1']"
        assert_select "input[type=hidden][name=project_id][value='#{project.id}']"
        assert_select "input[type=hidden][name='shown[]'][value=nps]"
        assert_select "input[type=radio][name='nps_response[score]']", 11
        assert_select "textarea[required]", 2
        assert_select "textarea.optional:not([required])", 1
        assert_select "button[type=submit]", "send"
      end
    end
    assert_match "tell us how playground is going", css_select("#ship-check-nps").text.squish
    assert_select "#ship-checks button[disabled]", "ship"
    assert_select "#ship-checks [role=status]", "fix these first"

    # The server holds the ship too.
    post ship_project_path(project), headers: STREAM
    assert_response :unprocessable_entity
    assert_select "#ship-checks .banner.alert", "not yet: tell us how playground is going"
    assert_empty project.ships
  end

  test "an answer sent from the ship list saves in place, ticks the step, and lets the pet ship" do
    user, project = ready_to_ship
    post nps_path, params: { checks: 1, project_id: project.id, shown: %w[nps], nps_response: ANSWER.merge(score: "2") }, headers: STREAM
    assert_redirected_to checks_project_path(project, shown: %w[nps])
    assert_response :see_other
    answer = NpsResponse.sole
    assert_equal [ user, 2, "ship", project ], [ answer.user, answer.score, answer.source, answer.project ]

    follow_redirect!(headers: STREAM.dup)
    assert_equal "text/vnd.turbo-stream.html", response.media_type
    assert_select "#ship-check-nps.ok" do
      assert_select ".icon", "✓"
      assert_select "p.fix", "thanks! 🪨"
      assert_select "form", 0
    end
    assert_select "#ship-checks form[action='#{ship_project_path(project)}'] button", /\Aship /

    post ship_project_path(project), headers: STREAM
    assert_redirected_to project_path(project)
    assert project.ships.sole.pending?
    assert_equal 1, NpsResponse.count
  end

  test "an answer missing a part from the ship list is not saved, and the step says so" do
    _, project = ready_to_ship
    post nps_path, params: { checks: 1, project_id: project.id, shown: %w[nps], nps_response: ANSWER.merge(doing_well: " ") }, headers: STREAM
    assert_redirected_to checks_project_path(project, shown: %w[nps])
    assert_empty NpsResponse.all
    follow_redirect!(headers: STREAM.dup)
    assert_select "#ship-check-nps.todo .banner.alert", "pick a number and fill in the * ones first."

    other = User.create!(hca_id: "ident!other", email: "o@example.com").projects.create!(name: "theirs")
    post nps_path, params: { checks: 1, project_id: other.id, nps_response: ANSWER }
    assert_response :not_found
    assert_empty NpsResponse.all
  end

  test "an answer 11 hours 59 minutes ago spares the ship, and one 12 hours 1 minute ago does not" do
    user, project = ready_to_ship
    answer = NpsResponse.create!(user:, score: 8, doing_well: "a", improve: "b", source: "daily", created_at: 12.hours.ago + 1.minute)
    get checks_project_path(project), headers: STREAM
    assert_select "#ship-checks li[data-check]", 0

    answer.update_columns(created_at: 12.hours.ago - 1.minute)
    get checks_project_path(project), headers: STREAM
    assert_select "#ship-check-nps.todo"
    post ship_project_path(project), headers: STREAM
    assert_response :unprocessable_entity
    assert_empty project.ships

    answer.update_columns(created_at: 12.hours.ago + 1.minute)
    post ship_project_path(project), headers: STREAM
    assert_redirected_to project_path(project)
    assert_equal 1, project.ships.count
  end

  private

  def ready_to_ship
    user = log_in("participant")
    post dev_hackatime_path
    [ user, user.projects.create!(READY.merge(name: "rock")) ]
  end
end
