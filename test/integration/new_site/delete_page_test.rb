require "test_helper"

# A pet is deleted from its edit page: delete sits beside save and cancel,
# and asks first on a page of its own, with no popup. A shipped pet has no
# delete, and the server refuses to delete it.
class NewSiteDeletePageTest < ActionDispatch::IntegrationTest
  include NewSiteTests
  setup { @user = log_in("participant") }

  test "delete sits beside save and cancel, inside the edit form's buttons, and leads to a page that asks first" do
    project = @user.projects.create!(name: "rock")
    get edit_project_path(project)
    assert_select "form.stack .form-buttons" do
      assert_select "input[type=submit][value=save]"
      assert_select "a.btn", "cancel"
      assert_select "a.btn.danger[href=?]", delete_project_path(project), "delete"
    end
    # The edit page holds one form, and nothing on it deletes or pops up.
    assert_select "form form", 0
    assert_select "form[action=?] input[name=_method][value=delete]", project_path(project), 0
    assert_select "dialog", 0

    get delete_project_path(project)
    assert_response :ok
    assert_select ".page-window h2", "delete rock?"
    assert_select ".page-window p", /rock will be gone forever/
    assert_select "form[action=?] input[name=_method][value=delete]", project_path(project)
    assert_select "form[action=?] button.btn.danger", project_path(project), "delete it"
    assert_select "a.btn[href=?]", edit_project_path(project), "keep it"
    assert_select "dialog", 0
  end

  test "deleting an unshipped pet lands on my pets" do
    project = @user.projects.create!(name: "rock")
    delete project_path(project)
    assert_redirected_to projects_path
    assert_not Project.exists?(project.id)
  end

  test "a shipped pet has no delete, and the server refuses to delete it" do
    project = @user.projects.create!(name: "rock")
    project.ships.create!(user: @user)
    get edit_project_path(project)
    assert_select "a", text: "delete", count: 0
    assert_select "dialog", 0

    get delete_project_path(project)
    assert_redirected_to edit_project_path(project)
    assert_equal "a shipped pet cannot be deleted", flash[:alert]

    delete project_path(project)
    assert_redirected_to projects_path(anchor: "pet-#{project.id}")
    assert_equal "a shipped pet cannot be deleted", flash[:alert]
    assert Project.exists?(project.id)
  end
end
