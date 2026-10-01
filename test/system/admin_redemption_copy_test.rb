require "application_system_test_case"

# On the fulfillment page, after the reveal, "copy all" copies the parcel's
# address alone, and each way to reach the participant copies by its button
# or its key. A key typed into a field is only typing.
class AdminRedemptionCopyTest < ApplicationSystemTestCase
  setup do
    user = User.create!(hca_id: "ident!copy", email: "sam@example.com", slack_id: "U0SAMROCK", verification_status: "verified", ysws_eligible: true)
    @redemption = user.redemptions.create!(goal_key: "stickers", address: {
      "first_name" => "Sam", "last_name" => "Rock", "line_1" => "15 Falls Road", "line_2" => "Flat 2", "city" => "Burlington",
      "state" => "VT", "postal_code" => "05401", "country" => "US", "phone_number" => "+1 802 555 0100"
    })
    visit dev_login_path(as: "admin", admin: 1)
    assert_selector ".adminnav"
    visit admin_redemption_path(@redemption)
    assert_no_selector "table.contact"
    click_button "reveal address"
    assert_selector "table.contact"
    # The page's copies land here instead of the clipboard, which a headless
    # browser keeps to itself.
    page.execute_script("window.copied = []; navigator.clipboard.writeText = (text) => (window.copied.push(text), Promise.resolve())")
  end

  test "copy all copies the address without the contact details, and each contact button copies its own" do
    click_button "copy all"
    assert_selector "button[data-shortcut=y]", text: "copied ✓"
    within("table.contact") { all("button").each(&:click) }
    assert_equal [ "Sam Rock\n15 Falls Road\nFlat 2\nBurlington\nVT\n05401\nUS", "sam@example.com", "+1 802 555 0100", "U0SAMROCK" ], copied
    assert_selector "table.contact button", text: "copied ✓", count: 3
    # The label comes back after a moment.
    assert_selector "table.contact button", exact_text: "copy", count: 3
  end

  test "e, m, and k copy the email, the phone, and the Slack ID, and not while typing in a field" do
    find("body").send_keys("e")
    # The label shows for 1.5s, so it is checked before the other keys.
    assert_selector "button[data-shortcut=e]", text: "copied ✓"
    find("body").send_keys("m")
    find("body").send_keys("k")
    assert_equal [ "sam@example.com", "+1 802 555 0100", "U0SAMROCK" ], copied
    # Twice in a row, the label still comes back.
    find("body").send_keys("e")
    assert_selector "button[data-shortcut=e]", exact_text: "copy"

    fill_in "tracking", with: "emk"
    assert_equal 4, copied.size, "typing in a field copies nothing"
    assert_field "tracking", with: "emk"
  end

  private

  def copied = page.evaluate_script("window.copied")
end
