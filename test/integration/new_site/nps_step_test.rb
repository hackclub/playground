require "test_helper"

# The new site's ship list has the same step for the NPS form as the
# desktop's, and an answer sent from the guide's Ship it step goes back to
# the guide's list.
class NewSiteNpsStepTest < ActionDispatch::IntegrationTest
  include NewSiteTests
  STREAM = { "Accept" => "text/vnd.turbo-stream.html, text/html, application/xhtml+xml" }.freeze
  READY = { description: "a rock that walks along your taskbar", code_url: "https://github.com/pet/rock",
            ship_message_url: "https://hackclub.slack.com/archives/C0C51NCK1DG/p1759012345678901", playable_url: "https://pet.itch.io/rock", hackatime_projects: [ "rock-pet" ],
            screenshots: [ { "id" => "shot", "key" => "shot.webp", "url" => "https://playground.hackclub-assets.com/shot.webp" } ] }.freeze

  setup do
    NpsResponse.asking = true
    @user = log_in("participant")
    post dev_hackatime_path
    @project = @user.projects.create!(READY.merge(name: "rock"))
  end

  test "the ship page lists the step with its questions, and an answer from the guide goes back to the guide's list" do
    get ship_project_path(@project)
    assert_select "#ship-check-nps.todo form.nps-fix[action='#{nps_path}']" do
      assert_select "input[type=radio][name='nps_response[score]']", 11
      assert_select "input[type=hidden][name=from]", 0
    end

    get checks_project_path(@project, from: "guide"), headers: STREAM
    assert_select "#ship-check-nps form.nps-fix input[type=hidden][name=from][value=guide]"

    post nps_path, params: { checks: 1, project_id: @project.id, from: "guide", shown: %w[nps],
                             nps_response: { score: "7", doing_well: "the guide", improve: "more steps" } }, headers: STREAM
    assert_redirected_to checks_project_path(@project, from: "guide", shown: %w[nps])
    assert_equal [ 7, "ship", @project ], NpsResponse.sole.then { [ it.score, it.source, it.project ] }
    follow_redirect!(headers: STREAM.dup)
    assert_select "#ship-check-nps.ok"
    assert_select "#ship-checks form[action^='#{ship_project_path(@project)}'] button", /\Aship /
  end
end
