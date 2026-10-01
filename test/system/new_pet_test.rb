require "application_system_test_case"

# A new pet asks for its name and description only. Create lands on the pet
# page, and edit adds the rest.
class NewPetTest < ApplicationSystemTestCase
  setup do
    log_in_as "participant"
    @user = User.find_by!(hca_id: "ident!dev-participant")
  end

  test "a new pet made in ship.exe starts with a name and a description, opens in its own window, and edit adds the rest" do
    @user.update!(hackatime_access_token: "fake")
    visit root_path(open: "goal")

    within_frame(find(".ship-frame")) do
      click_link "+ new pet"
      assert_selector "h2", text: "new pet"
      assert_field "project[description]"
      assert_no_field "project[code_url]"
      assert_no_field "project[playable_url]"
      assert_no_selector ".picker, input[type=file]", visible: :all
      fill_in "project[name]", with: "rock"
      fill_in "project[description]", with: "a rock that walks along your taskbar"
      click_button "create pet"
    end

    # ship.exe goes back to its list, and the new pet opens in a window of its own.
    within_frame(find(".ship-frame")) { assert_link "rock" }
    within_frame(find("#window-pet-#{@user.projects.sole.id} iframe")) do
      assert_text "Hackatime: none linked"
      assert_selector "body.in-window"
      click_link "edit"
      fill_in "project[code_url]", with: "https://github.com/pet/rock"
      fill_in "project[playable_url]", with: "https://github.com/pet/rock/releases/latest"
      find("input[type=checkbox][value='rock-pet']").check
      click_button "save"

      assert_text "Hackatime: rock-pet"
    end
    assert_selector "#welcome", count: 1
    assert_equal "https://github.com/pet/rock", @user.projects.sole.code_url
  end

  test "a name and a description with no spaces wrap on a phone" do
    project = @user.projects.create!(name: "x" * 80, description: "y" * 2000)
    page.current_window.resize_to(390, 844)
    visit project_path(project)
    assert_link "ship"
    assert page.evaluate_script("document.documentElement.scrollWidth <= document.documentElement.clientWidth"),
           "long words wrap instead of scrolling the page sideways"
  ensure
    page.current_window.resize_to(1440, 900)
  end
end
