require "test_helper"

# A pet is deleted from its edit page, with a form of its own below the edit
# form. A shipped pet has no delete button, and the server refuses to delete it.
class DeletePetTest < ActionDispatch::IntegrationTest
  setup { @user = log_in("participant") }

  test "the delete button is on the edit page, outside the edit form, and not on the pet page" do
    project = @user.projects.create!(name: "rock")
    get edit_project_path(project)
    assert_select "form.button_to[action='#{project_path(project)}'] input[name=_method][value=delete]", 1
    assert_select "form.button_to button", "delete pet"
    assert_select "form form", 0
    assert_select "dialog.popup[role=alertdialog][data-controller=popup-drag] .popup-head[data-popup-drag-target=head]", 3
    assert_select "[data-turbo-confirm]", 0

    get project_path(project)
    assert_select "button", text: "delete pet", count: 0
  end

  test "deleting an unshipped pet lands on the dashboard" do
    project = @user.projects.create!(name: "rock")
    delete project_path(project)
    assert_redirected_to dashboard_path
    assert_not Project.exists?(project.id)
  end

  test "a shipped pet has no delete button, and the server refuses to delete it" do
    project = @user.projects.create!(name: "rock")
    project.ships.create!(user: @user)
    get edit_project_path(project)
    assert_select "button", text: "delete pet", count: 0
    assert_select "dialog.popup", 0

    delete project_path(project)
    assert_redirected_to project_path(project)
    assert_equal "a shipped pet cannot be deleted", flash[:alert]
    assert Project.exists?(project.id)
  end
end
