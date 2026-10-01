require "application_system_test_case"

# The icon that was Bounty is Fulfillment, with the same picture and form. It
# keeps the key of its first label, so a layout or a trash saved before the
# rename still finds it: in this browser, and on a participant's account.
class FulfillmentIconTest < ApplicationSystemTestCase
  FORM = "https://forms.hackclub.com/bounty".freeze

  test "the icon and the text link say Fulfillment, and open the same form" do
    visit root_path
    icon = find(".app", exact_text: "Fulfillment")
    assert_equal FORM, icon[:href]
    assert_includes icon.find(".appicon")[:src], "/landing/bounty-"
    assert_no_selector ".app", exact_text: "Bounty"
    assert_selector "#credit-links a[href='#{FORM}']", exact_text: "Fulfillment", visible: :all
    assert_no_text "Bounty"
  end

  test "a layout and a trash saved under Bounty still find it" do
    visit root_path
    page.execute_script("localStorage.setItem('playground-desktop-icons', JSON.stringify({ Bounty: [3, 1] }))")
    visit root_path
    assert_equal "3,1", find(".app", exact_text: "Fulfillment")["data-cell"]

    page.execute_script("localStorage.setItem('playground-desktop-trash', JSON.stringify(['Bounty']))")
    visit root_path
    assert_no_selector ".app", exact_text: "Fulfillment"
    find(".app[data-key=trash]").click
    assert_selector "#trash-menu [role=menuitem]", exact_text: "restore Fulfillment"

    # Signed in, the trash on the account works the same.
    user = log_in_as "participant"
    # The banana peel taken out, so the trash holds only Bounty.
    user.update!(desktop_trash: [ "Bounty" ], banana_peel_out: true)
    visit root_path
    assert_no_selector ".app", exact_text: "Fulfillment"
    find(".app[data-key=trash]").click
    click_button "restore Fulfillment"
    assert_selector ".app", exact_text: "Fulfillment"
    deadline = Time.now + Capybara.default_max_wait_time
    sleep 0.05 until user.reload.desktop_trash.empty? || Time.now > deadline
    assert_empty user.desktop_trash
  end
end
