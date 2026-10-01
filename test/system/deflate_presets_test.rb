require "application_system_test_case"

# The review page's presets in a real browser: a click fills the approved
# hours field with that share of the claimed hours.
class DeflatePresetsTest < ApplicationSystemTestCase
  test "each preset fills the approved hours, and the reviewer can still type" do
    participant = User.create!(hca_id: "ident!defl", email: "defl@example.com", verification_status: "verified", ysws_eligible: true)
    ship = participant.projects.create!(name: "rock").ships.create!(user: participant, claimed_seconds: 4 * 3600)
    visit dev_login_path(as: "admin", admin: 1)
    visit admin_ship_path(ship, stage: "review")
    assert_field "approved_hours", with: "4.0"
    { 15 => "0.6", 30 => "1.2", 50 => "2", 75 => "3" }.each do |percent, hours|
      find("button[data-percent='#{percent}']").click
      assert_field "approved_hours", with: hours
    end
    fill_in "approved_hours", with: "1.1"
    assert_field "approved_hours", with: "1.1"
  end
end
