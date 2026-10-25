require "test_helper"

# Prize claiming closes 14 days after the program window ends.
class RedeemCloseTest < ActionDispatch::IntegrationTest
  WINDOW = ProgramWindow.load({ starts_at: "2026-09-25 17:00", ends_at: "2026-10-19 02:00" })
  SHIPPING = { shipping: { first_name: "Sam", last_name: "Dev", line_1: "15 Falls Road", city: "Shelburne", country: "US" } }.freeze

  setup do
    ProgramWindow.current = WINDOW
    @user = log_in("participant")
    project = @user.projects.create!(name: "p", tracked_seconds: 3 * 3600)
    admin = User.create!(hca_id: "ident!close-admin", admin: true)
    ship = project.ships.create!(user: @user, claimed_seconds: 3 * 3600)
    ship.approve_review!(by: admin, seconds: 3 * 3600, judgement: "ok", feedback: nil)
    ship.pass_fraud!(by: admin)
  end

  test "a redemption just before the close works" do
    travel_to WINDOW.redeem_ends_at - 1.minute
    get dashboard_path
    assert_select "a[href=?]", new_redemption_path(goal_key: "stickers")
    get new_redemption_path(goal_key: "stickers")
    assert_response :success
    post redemptions_path(goal_key: "stickers"), params: SHIPPING
    assert_redirected_to dashboard_path
    assert_match "redeemed", flash[:notice]
    assert_equal 1, @user.redemptions.count
  end

  test "a redemption at or after the close is refused" do
    [ WINDOW.redeem_ends_at, WINDOW.redeem_ends_at + 1.day ].each do |at|
      travel_to at
      get new_redemption_path(goal_key: "stickers")
      assert_redirected_to dashboard_path
      assert_equal "prize claiming closed on November 2", flash[:alert]
      post redemptions_path(goal_key: "stickers"), params: SHIPPING
      assert_redirected_to dashboard_path
      assert_equal "prize claiming closed on November 2", flash[:alert]
    end
    assert_empty @user.redemptions
  end

  test "no redeem button shows after the close, and a made redemption stays" do
    @user.redemptions.create!(goal_key: "stickers", address: { "line_1" => "1 Road" })
    travel_to WINDOW.redeem_ends_at
    get dashboard_path
    assert_select "a[href=?]", new_redemption_path(goal_key: "stickers"), 0
    assert_select ".badge", /redeemed/
    assert_equal 1, @user.redemptions.count
  end

  test "an unredeemed goal shows a closed line instead of the button" do
    travel_to WINDOW.redeem_ends_at
    get dashboard_path
    assert_select "a[href=?]", new_redemption_path(goal_key: "stickers"), 0
    assert_select ".goal .muted", "claiming closed Nov 2"
  end
end
