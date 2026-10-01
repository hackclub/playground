require "test_helper"

# Turbo shows its copy of a page it has left while the page loads again.
# A page with fields to type in opts out, so nothing typed into the copy is
# lost when the page arrives.
class TurboPreviewTest < ActionDispatch::IntegrationTest
  NO_PREVIEW = "meta[name='turbo-cache-control'][content='no-preview']".freeze

  setup do
    @user = log_in("participant")
    @project = @user.projects.create!(name: "rock")
  end

  test "the pages with fields keep out of the preview, and the others keep it" do
    [ new_project_path, edit_project_path(@project), checks_project_path(@project), checks_project_path(@project, window: 1) ].each do |path|
      get path
      assert_select NO_PREVIEW, 1, path
    end

    [ dashboard_path, project_path(@project) ].each do |path|
      get path
      assert_select NO_PREVIEW, 0, path
    end
  end
end
