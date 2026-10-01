require "test_helper"

# Code off GitHub has no README or commits to show, so the review page gives
# the reviewer a plain link to read it by hand.
class AdminCodeLinkTest < ActionDispatch::IntegrationTest
  test "a ship with code on GitLab shows a plain link to it and no commit list" do
    participant = User.create!(hca_id: "ident!code-link", verification_status: "verified", ysws_eligible: true)
    project = participant.projects.create!(name: "rock", code_url: "https://gitlab.com/pet/rock")
    ship = project.ships.create!(user: participant, claimed_seconds: 3600, snapshot: { "code_url" => project.code_url })
    log_in("admin")

    get admin_ship_path(ship, stage: "review")
    assert_response :success
    assert_select "p.muted", /no GitHub data/ do
      assert_select "a[href='https://gitlab.com/pet/rock'][target=_blank][rel=noopener]", "https://gitlab.com/pet/rock"
    end
    assert_select "summary", text: /recent commits/, count: 0
  end
end
