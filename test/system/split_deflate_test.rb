require "application_system_test_case"

# Coding and art deflate apart on the review page. Changing coding moves the
# art limit live (art is held at 30% of the total), and each preset row moves
# only its own field.
class SplitDeflateTest < ApplicationSystemTestCase
  setup do
    participant = User.create!(hca_id: "ident!split-sys", email: "ss@example.com", verification_status: "verified", ysws_eligible: true)
    @ship = participant.projects.create!(name: "rock").ships.create!(
      user: participant, claimed_seconds: 5 * 3600, snapshot: { "ai_coding_seconds" => 0, "lapse_seconds" => 2 * 3600, "lapses" => [] })
    visit dev_login_path(as: "admin", admin: 1)
    visit admin_ship_path(@ship, stage: "review")
  end

  test "the coding presets leave art alone, but lower it when it passes the limit" do
    assert_field "approved_hours", with: "3.0"
    assert_field "approved_art_hours", with: "1.29"
    find("button[data-percent='50']").click
    assert_field "approved_hours", with: "1.5"
    assert_field "approved_art_hours", with: "0.64"
    assert_text "art held at 30% of the total"
    assert_selector "[data-deflate-target=total]", text: "2.14"
  end

  test "the art presets leave coding alone" do
    find("button[data-art-percent='30']").click
    assert_field "approved_art_hours", with: "0.6"
    assert_field "approved_hours", with: "3.0"
    assert_selector "[data-deflate-target=total]", text: "3.6"
    fill_in "approved_art_hours", with: "5"
    assert_field "approved_art_hours", with: "1.29"
  end
end
