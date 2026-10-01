require "test_helper"

class HoursTest < ActiveSupport::TestCase
  setup do
    @user = User.create!(hca_id: "ident!hours")
    @project = @user.projects.create!(name: "p", tracked_seconds: 0)
    @admin = User.create!(hca_id: "ident!hours-admin", admin: true)
  end

  def approve(seconds)
    ship = @project.ships.create!(user: @user, claimed_seconds: seconds)
    ship.approve_review!(by: @admin, seconds:, judgement: "ok", feedback: nil)
    ship.pass_fraud!(by: @admin)
    @project.update_columns(tracked_seconds: @project.claimed_by)
  end

  test "a goal moves from in progress, to ship, to in review, to redeemable" do
    stickers = Goal.find("stickers")
    @project.update_columns(tracked_seconds: 3600)
    assert_equal :in_progress, @user.hours.goal_state(stickers)

    @project.update_columns(tracked_seconds: 7200)
    assert_equal :ship_to_redeem, @user.hours.goal_state(stickers)

    @project.ships.create!(user: @user, claimed_seconds: 7200)
    assert_equal :in_review, Hours.new(@user.reload).goal_state(stickers)

    @project.ships.last.tap { it.approve_review!(by: @admin, seconds: 7200, judgement: "ok", feedback: nil) }.pass_fraud!(by: @admin)
    assert_equal :redeemable, Hours.new(@user.reload).goal_state(stickers)
  end

  test "the meter ends at the last goal, whatever the total" do
    @project.update_columns(tracked_seconds: 217 * 3600)
    hours = @user.hours
    assert_equal Goal.all.last.seconds, hours.scale_seconds
    assert_equal 207 * 3600, hours.beyond_scale_seconds
  end
end
