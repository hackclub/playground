require "application_system_test_case"

# The pet list in ship.exe: every pet has an edit button, whatever its state,
# and the button opens the edit page in the pet's own window, as the pet's
# name opens its page there.
class DashboardPetsTest < ApplicationSystemTestCase
  test "each pet's edit button opens its edit page in the pet's own window, and ship.exe keeps the list" do
    log_in_as "participant"
    within_frame(find(".ship-frame")) do
      assert_text "no pets yet."
      assert_no_link "edit"
    end

    user = User.find_by!(hca_id: "ident!dev-participant")
    user.projects.create!(name: "draft pet")
    Ship::STATES.each { |state| user.projects.create!(name: "#{state} pet").ships.create!(user: user, state: state) }
    visit root_path(open: "goal")

    within_frame(find(".ship-frame")) do
      assert_selector ".pets li", count: 1 + Ship::STATES.size
      user.projects.each do |project|
        within(".pets li", text: project.name) do
          assert_selector "a.btn[href='#{edit_project_path(project)}'][aria-label='edit #{project.name}']", text: "edit"
        end
      end
      within(".pets li", text: "changes_needed pet") { click_link "edit" }
    end
    pet = user.projects.find_by!(name: "changes_needed pet")
    within_frame(find("#window-pet-#{pet.id} iframe")) { assert_selector "h2", text: "edit changes_needed pet" }
    within_frame(find(".ship-frame")) do
      assert_text "your pets"
      assert_no_selector "h2", text: "edit"
    end
    assert_selector "#welcome", count: 1
  end

  test "a pet name with no spaces wraps inside ship.exe" do
    log_in_as "participant"
    User.find_by!(hca_id: "ident!dev-participant").projects.create!(name: "x" * 80)
    visit root_path(open: "goal")

    within_frame(find(".ship-frame")) do
      assert_link "edit"
      assert page.evaluate_script("document.documentElement.scrollWidth <= document.documentElement.clientWidth"),
             "the long name wraps instead of scrolling the window sideways"
    end
  end
end
