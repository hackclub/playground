require "test_helper"

# A participant may never have heard of Hack Club, so no page they see uses
# its program words, such as "ysws". The admin pages are for reviewers, who
# know them.
class PlainWordsTest < ActionDispatch::IntegrationTest
  JARGON = /\bysws\b/i

  test "no page a participant sees says ysws, signed out or in, verified or not" do
    get root_path
    refute_jargon root_path
    get dashboard_path
    refute_jargon dashboard_path

    user = log_in("unverified")
    project = user.projects.create!(name: "rock")
    [ root_path, dashboard_path, new_project_path, project_path(project), edit_project_path(project),
      checks_project_path(project), checks_project_path(project, window: 1), trash_project_path(project) ].each do |path|
      get path
      assert_response :success
      refute_jargon path
    end
    get checks_project_path(project)
    assert_select "#ship-check-eligible", /your identity needs to be verified, and your account eligible/
  end

  test "the redeem form says no ysws either" do
    user = log_in("participant")
    project = user.projects.create!(name: "p", tracked_seconds: 3 * 3600)
    admin = User.create!(hca_id: "ident!plain-admin", admin: true)
    ship = project.ships.create!(user:, claimed_seconds: 3 * 3600)
    ship.approve_review!(by: admin, seconds: 3 * 3600, judgement: "ok", feedback: nil)
    ship.pass_fraud!(by: admin)
    get new_redemption_path(goal_key: "stickers")
    assert_response :success
    refute_jargon new_redemption_path
  end

  test "the desktop's scripts and the error pages say no ysws" do
    files = Dir[Rails.root.join("app/javascript/**/*.js")] + Dir[Rails.root.join("public/*.html")]
    assert_operator files.size, :>, 10
    files.each do |file|
      # Comments are for whoever reads the code, not for participants.
      text = File.read(file).gsub(%r{/\*.*?\*/}m, "").gsub(%r{^\s*//.*$}, "")
      refute_match JARGON, text, file
    end
  end

  private

  def refute_jargon(path) = refute_match(JARGON, response.body, path)
end
