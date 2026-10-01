require "application_system_test_case"

# The edit page's "link it again" sits inside the pet form but submits the
# relink form that follows it, so the pet is not saved on the way to
# Hackatime. With fake services, a token of "revoked" is one Hackatime refuses.
class HackatimeRelinkTest < ApplicationSystemTestCase
  test "link it again on the edit page relinks Hackatime and leaves the pet alone" do
    user = log_in_as "participant"
    user.update!(hackatime_access_token: "revoked")
    project = user.projects.create!(name: "rock", description: "naps on your windows")

    visit edit_project_path(project)
    assert_text "Hackatime can't see your account through this link."
    fill_in "project[name]", with: "not saved"
    page.execute_script("document.body.dataset.beforeRelink = ''")
    click_button "link it again"

    assert_no_selector "body[data-before-relink]"
    assert_selector "#welcome"
    within_frame(find(".ship-frame")) { assert_text "fake Hackatime linked" }
    assert_equal "fake", user.reload.hackatime_access_token
    assert_equal "rock", project.reload.name
  end
end
