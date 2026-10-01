require "application_system_test_case"

# Only Hackatime time inside the program window counts. Before it starts,
# ship.exe's meter is empty and says when time starts to count. The picker
# lists only projects with time in the window, and keeps the pet's own.
class ProgramTimePagesTest < ApplicationSystemTestCase
  test "before the start, ship.exe's meter is empty and says when time starts to count" do
    ProgramWindow.current = ProgramWindow.load({ starts_at: "2099-09-25 17:00", ends_at: "2099-10-09 17:00" })
    user = log_in_as "participant"
    user.update!(hackatime_access_token: "fake")
    user.projects.create!(name: "rock", hackatime_projects: %w[rock-pet])
    visit root_path(open: "goal")
    within_frame(find(".ship-frame")) do
      within(".panel", text: "your meter") do
        assert_text "time counts from 5pm Eastern time on September 25, 2099."
        assert_text "unshipped 0m"
      end
      assert_selector ".pets li", text: "0m unshipped"
    end
  end

  test "the edit page lists only projects with time in the window, and a save keeps the pet's own" do
    # rock-pet and rock-pet-art have time in the last three hours. frog-widget
    # and dotfiles do not.
    ProgramWindow.current = ProgramWindow.new(starts_at: 3.hours.ago, ends_at: 1.day.from_now)
    user = log_in_as "participant"
    user.update!(hackatime_access_token: "fake")
    pet = user.projects.create!(name: "rock", hackatime_projects: %w[dotfiles])
    visit edit_project_path(pet)

    within("ul.picker") do
      assert_equal %w[rock-pet rock-pet-art dotfiles], all("li strong").map(&:text)
      assert_selector "li", text: /rock-pet-art\s+50m · last active about 2 hours ago/
      assert_selector "li", text: /dotfiles\s+no time counted yet/
      assert find("input[value=dotfiles]").checked?
    end
    assert_no_text "frog-widget"

    click_button "save"
    assert_selector "h2", text: "rock"
    assert_text "Hackatime: dotfiles"
    assert_equal %w[dotfiles], pet.reload.hackatime_projects
  end
end
