require "test_helper"

# An admin never judges their own ship or settles their own redemption, even
# by a direct post. Pages that hold an address are not kept in the browser's
# cache.
class AdminOwnItemsTest < ActionDispatch::IntegrationTest
  setup do
    @admin = log_in("admin")
  end

  test "an admin's own ship can't be reviewed or fraud-checked by that admin" do
    ship = @admin.projects.create!(name: "rock").ships.create!(user: @admin, claimed_seconds: 3600)
    post review_admin_ship_path(ship), params: { verdict: "approve", approved_hours: 1, judgement: "mine", feedback: "mine" }
    assert_redirected_to admin_ship_path(ship)
    assert_equal "someone else judges your own ship", flash[:alert]
    ship.update!(review_status: "approved", fraud_status: "pending")
    post fraud_admin_ship_path(ship), params: { verdict: "pass" }
    assert_redirected_to admin_ship_path(ship)
    assert ship.reload.pending?
  end

  test "an admin's own redemption can't be settled by that admin" do
    r = @admin.redemptions.create!(goal_key: "stickers", address: { "line_1" => "15 Falls Road" })
    post verdict_admin_redemption_path(r), params: { verdict: "fulfill", tracking: "x" }
    assert_redirected_to admin_redemption_path(r)
    assert_equal "someone else settles your own redemption", flash[:alert]
    assert_equal "pending", r.reload.status
  end

  test "the address pages tell the browser not to store them" do
    r = User.create!(hca_id: "ident!cache").redemptions.create!(goal_key: "stickers", address: { "line_1" => "15 Falls Road" })
    post reveal_admin_redemption_path(r)
    assert_includes response.headers["Cache-Control"], "no-store"
    get new_redemption_path(goal_key: "stickers")
    assert_includes response.headers["Cache-Control"], "no-store"
  end

  test "a shared Hackatime account shows on the review page" do
    @admin.update!(hackatime_user_id: "hk-1")
    other = User.create!(hca_id: "ident!twin", hackatime_user_id: "hk-1")
    ship = other.projects.create!(name: "twin").ships.create!(user: other, claimed_seconds: 3600)
    get admin_ship_path(ship, stage: "fraud")
    assert_select ".warnbox h2", "same Hackatime account elsewhere"
  end
end
