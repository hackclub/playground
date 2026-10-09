require "test_helper"

# The new site's rock, which asks for the NPS form in nps.exe's place: on
# the guide between the step and its buttons, at the end of any other page,
# and on no page that asks already. Its popup sends the answer from a
# script, which gets only a status back. The old desktop is unchanged.
class NewSiteNpsRockTest < ActionDispatch::IntegrationTest
  include NewSiteTests
  ANSWER = { score: "9", doing_well: "the guide's videos", improve: "more pet ideas", anything_else: "" }.freeze
  JSON = { "Accept" => "application/json" }.freeze

  setup do
    NpsResponse.asking = true
    @user = log_in("participant")
    CodingHour.create!(user: @user, hour: 1.day.ago.beginning_of_hour, seconds: 600)
  end

  test "the guide places the rock once, between the step and its buttons, with feedback.exe's form" do
    get guide_path
    assert_select ".nps-ask", 1
    assert_select ".hub-main > .nps-ask + .guide-pager"
    assert_select ".nps-ask[hidden][data-controller=nps-rock][data-nps-rock-store-value='playground-nps-asked:#{@user.id}']"
    assert_select ".nps-ask .nps-rock[aria-haspopup=dialog] img.nps-rock-img[src*='landing/rock']"
    assert_select ".nps-ask .nps-bin img.nps-bin-empty[src*='trash-empty']"
    assert_select ".nps-ask .nps-bin img.nps-bin-full[src*='trash-full']"
    assert_select ".nps-ask .nps-strip .nps-strip-box", 11
    assert_select ".nps-ask dialog.popup.nps-popup .popup-title", "feedback.exe"
    assert_select ".nps-ask dialog form[action='#{nps_path}']" do
      assert_select "input[type=radio][name='nps_response[score]']", 11
      assert_select "input#nps_rock_score_10"
      NpsResponse::QUESTIONS.each_key { |key| assert_select "label[for=nps_rock_#{key}] + textarea#nps_rock_#{key}" }
      assert_select "input[name=checks]", 0
    end
  end

  test "any other page has it at its end, and the form's own page and a ship page have none" do
    get root_path
    assert_select "main.page > .nps-ask:last-child"
    get projects_path
    assert_select "main.page > .nps-ask:last-child"

    get nps_path
    assert_select ".nps-ask", 0
    assert_select "#nps_response_score_0"
    project = @user.projects.create!(name: "rock")
    get ship_project_path(project)
    assert_select "#ship-checks"
    assert_select ".nps-ask", 0
  end

  test "only for a participant nps.exe would ask by itself" do
    NpsResponse.create!(user: @user, score: 8, doing_well: "a", improve: "b", source: "daily")
    get guide_path
    assert_select ".nps-ask", 0, "answered in the last 12 hours"
    NpsResponse.update_all(created_at: 13.hours.ago)
    get guide_path
    assert_select ".nps-ask", 1

    CodingHour.where(user: @user).delete_all
    get guide_path
    assert_select ".nps-ask", 0, "no Hackatime time yet"

    log_in("admin")
    CodingHour.create!(user: User.find_by!(hca_id: "ident!dev-admin"), hour: 1.day.ago.beginning_of_hour, seconds: 600)
    get guide_path
    assert_select ".nps-ask", 0, "an admin"

    delete logout_path
    get guide_path
    assert_select ".nps-ask", 0, "signed out"
  end

  test "the popup's answer saves as a daily one, and gets a status back" do
    post nps_path, params: { nps_response: ANSWER }, headers: JSON
    assert_response :created
    assert_equal [ 9, "daily", nil ], NpsResponse.sole.then { [ it.score, it.source, it.project ] }

    post nps_path, params: { nps_response: ANSWER.merge(improve: " ") }, headers: JSON
    assert_response :unprocessable_entity
    assert_equal 1, NpsResponse.count
  end

  test "the old desktop shows no rock" do
    @user.update!(new_site: false)
    get root_path
    assert_select "#apps[data-nps-ask]"
    assert_select ".nps-ask, .nps-rock", 0
    get nps_path
    assert_select "#nps_response_score_0"
    assert_select ".nps-ask", 0
  end
end
