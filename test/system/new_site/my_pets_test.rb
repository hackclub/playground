require "application_system_test_case"

# My pets in a real browser: the new pet tile is the size and shape of a
# pet's window. Beside pets it is as tall as the tallest in its row, and
# alone in a row it is as tall as a short pet.
class NewSiteMyPetsSystemTest < ApplicationSystemTestCase
  include NewSiteTests

  # Each tile's box, and its title bar's height, in CSS pixels.
  def tiles
    page.evaluate_script(<<~JS)
      [...document.querySelectorAll(".pet-list > li")].map(li => {
        const window = li.matches(".pet-new") ? li.querySelector("a") : li, box = window.getBoundingClientRect()
        return { new: li.matches(".pet-new"), top: box.top, width: box.width, height: box.height,
                 bar: window.querySelector(".pet-titlebar").getBoundingClientRect().height }
      })
    JS
  end

  setup do
    visit dev_login_path(as: "participant")
    @user = User.find_by!(hca_id: "ident!dev-participant")
    @user.projects.create!(name: "frog", hackatime_projects: [ "frog" ], tracked_seconds: 600, tracked_at: Time.current)
  end

  test "beside pets, the new pet tile is as wide, as tall as the tallest, and has the same title bar" do
    @user.projects.create!(name: "goose", tracked_at: Time.current, description: "a goose that honks at your windows " * 6)
    resize_viewport_to(1440, 900) do
      visit projects_path
      *pets, tile = tiles
      assert tile["new"]
      assert_equal [ tile["top"] ], pets.map { it["top"] }.uniq, "the tile shares the pets' row"
      assert_in_delta pets.map { it["width"] }.max, tile["width"], 0.5
      assert_in_delta pets.map { it["height"] }.max, tile["height"], 0.5
      assert_operator pets.map { it["height"] }.min, :<, tile["height"], "the pets differ in height"
      assert_equal pets.first["bar"], tile["bar"]
    end
  end

  test "alone in its row, as on a phone, the new pet tile is as tall as a short pet" do
    resize_viewport_to(390, 844) do
      visit projects_path
      pet, tile = tiles
      assert_operator tile["top"], :>, pet["top"]
      assert_in_delta pet["width"], tile["width"], 0.5
      assert_in_delta pet["height"], tile["height"], 1
    end
  end
end
