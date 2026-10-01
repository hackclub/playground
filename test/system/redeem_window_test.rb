require "application_system_test_case"

# A goal's redeem button in ship.exe opens that goal's own window with the
# shipping form. A redeem closes it, and ship.exe shows the notice and the
# goal redeemed. A refusal, on opening or on the redeem, closes it, and
# ship.exe shows why. A cancel closes it. A failed save keeps it open, with
# the error and what was typed. The address links stay inside it, and a
# second press raises it.
class RedeemWindowTest < ApplicationSystemTestCase
  # A second address on the fake Hack Club identity, for the "start from" links.
  module SecondAddress
    mattr_accessor :on
    def identity
      super.tap do |id|
        next unless SecondAddress.on
        id["addresses"] += [ { "id" => "addr_2", "first_name" => "Sam", "last_name" => "Dev", "line_1" => "2 Lake Street",
                               "city" => "Burlington", "state" => "VT", "postal_code" => "05401", "country" => "US" } ]
      end
    end
  end
  HackClubAuth::Fake.prepend(SecondAddress) unless HackClubAuth::Fake < SecondAddress

  setup do
    @user = log_in_as("participant")
    admin = User.create!(hca_id: "ident!redeem-admin", admin: true, first_name: "A")
    @ship = @user.projects.create!(name: "rock", tracked_seconds: 6 * 3600).ships.create!(user: @user, claimed_seconds: 6 * 3600)
    @ship.approve_review!(by: admin, seconds: 6 * 3600, judgement: "ok", feedback: nil)
    @ship.pass_fraud!(by: admin)
  end

  teardown { SecondAddress.on = false }

  test "redeem opens the goal's own window, and a redeem closes it and ship.exe shows the notice and the goal redeemed" do
    open_redeem "stickers"
    assert_selector "#window-redeem-stickers .headertext", exact_text: "stickers.redeem"
    within_frame(goal_frame) { assert_text "your meter" }
    within_frame(redeem_frame("stickers")) do
      assert_selector "h2", text: "redeem the stickersheet"
      assert_no_link "← dashboard"
      fill_in "shipping[first_name]", with: "Sam"
      click_button "redeem stickersheet"
    end
    assert_no_selector "#window-redeem-stickers"
    within_frame(goal_frame) do
      assert_selector ".flash.notice", count: 1, exact_text: "stickersheet redeemed! we'll ship it soon."
      assert_selector ".goal", text: /stickersheet.*redeemed · pending/m
    end
    assert_equal [ "stickers", "Sam" ], @user.redemptions.sole.then { [ it.goal_key, it.address["first_name"] ] }
  end

  # ship.exe's redeem buttons are as of its last load. A goal redeemed in
  # another tab since, or approved hours cut since, refuses on opening.
  test "a goal redeemed since ship.exe loaded: the window closes, and ship.exe says so and shows the goal redeemed" do
    visit root_path(open: "goal")
    within_frame(goal_frame) { assert_selector ".goal", text: /stickersheet.*redeem/m }
    @user.redemptions.create!(goal_key: "stickers", address: { "first_name" => "Sam" })
    press_redeem "stickers"
    within_frame(goal_frame) do
      assert_selector ".flash.alert", count: 1, exact_text: "you already redeemed the stickersheet"
      assert_selector ".goal", text: /stickersheet.*redeemed · pending/m
    end
    assert_no_selector "#window-redeem-stickers"
  end

  test "hours cut since ship.exe loaded: the window closes, and ship.exe says how many the goal needs" do
    visit root_path(open: "goal")
    within_frame(goal_frame) { assert_selector ".goal", text: /stickersheet.*redeem/m }
    @ship.update!(approved_seconds: 3600)
    press_redeem "stickers"
    within_frame(goal_frame) do
      assert_selector ".flash.alert", count: 1, exact_text: "you need 2 approved hours"
      assert_no_link "redeem"
    end
    assert_no_selector "#window-redeem-stickers"
  end

  test "a goal redeemed while its form was open: the redeem closes the window, and ship.exe says so" do
    open_redeem "stickers"
    @user.redemptions.create!(goal_key: "stickers", address: { "first_name" => "Sam" })
    within_frame(redeem_frame("stickers")) { click_button "redeem stickersheet" }
    assert_no_selector "#window-redeem-stickers"
    within_frame(goal_frame) { assert_selector ".flash.alert", count: 1, exact_text: "you already redeemed the stickersheet" }
    assert_equal 1, @user.redemptions.count
  end

  test "a failed save keeps the window open, with the error and what was typed" do
    open_redeem "stickers"
    within_frame(redeem_frame("stickers")) do
      fill_in "shipping[first_name]", with: "Samantha"
      fill_in "shipping[phone_number]", with: "call me"
      click_button "redeem stickersheet"
      assert_selector ".banner.alert", text: "Phone number should be digits"
      assert_field "shipping[first_name]", with: "Samantha"
      assert_field "shipping[phone_number]", with: "call me"
    end
    assert_selector "#window-redeem-stickers"
    assert_empty @user.redemptions
  end

  test "cancel closes the window and redeems nothing" do
    open_redeem "stickers"
    within_frame(redeem_frame("stickers")) { click_link "cancel" }
    assert_no_selector "#window-redeem-stickers"
    within_frame(goal_frame) { assert_text "your meter" }
    assert_empty @user.redemptions
  end

  test "a second press raises the open window and keeps what was typed" do
    open_redeem "stickers"
    within_frame(redeem_frame("stickers")) { fill_in "shipping[first_name]", with: "typed" }
    # The redeem window lies over ship.exe, so focus in ship.exe's page raises it.
    page.execute_script("document.querySelector('.ship-frame').contentDocument.querySelector('a').focus()")
    assert_front "window-goal.exe"
    open_redeem "stickers", visit: false
    assert_selector ".redeem-window", count: 1
    assert_front "window-redeem-stickers"
    within_frame(redeem_frame("stickers")) { assert_field "shipping[first_name]", with: "typed" }
  end

  test "the address links stay inside the window" do
    SecondAddress.on = true
    open_redeem "stickers"
    within_frame(redeem_frame("stickers")) do
      click_link "2 Lake Street, Burlington"
      assert_field "shipping[line_1]", with: "2 Lake Street"
    end
    assert_selector "#window-redeem-stickers"
    within_frame(goal_frame) { assert_text "your meter" }
  end

  test "outside the desktop, the redeem page is a page of its own with its way back" do
    visit new_redemption_path(goal_key: "stickers")
    assert_selector "h2", text: "redeem the stickersheet"
    click_link "← dashboard"
    assert_selector "h2", text: "your meter"
  end

  private

  def goal_frame = find(".ship-frame")

  def assert_front(id)
    page.document.synchronize do
      front = page.evaluate_script("[...document.querySelectorAll('.window')].filter((w) => w.style.display !== 'none').sort((a, b) => getComputedStyle(b).zIndex - getComputedStyle(a).zIndex)[0].id")
      raise Capybara::ExpectationNotMet, "#{front} is in front" unless front == id
    end
  end
  def redeem_frame(goal) = find("#window-redeem-#{goal} iframe")

  # The goal cards list the goals in order: the stickers first.
  def open_redeem(goal, visit: true)
    visit root_path(open: "goal") if visit
    press_redeem goal
    assert_selector "#window-redeem-#{goal}"
  end

  def press_redeem(goal)
    within_frame(goal_frame) { find(".goal", text: Goal.find(goal).name).find_link("redeem").send_keys(:enter) }
  end
end
