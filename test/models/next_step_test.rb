require "test_helper"

# The next step card's ship step names the prize with the most hours that
# all the participant's hours, approved, pending, and unshipped, would
# reach once approved, as the meter counts them, leaving out prizes already
# redeemed.
class NextStepTest < ActiveSupport::TestCase
  setup do
    @user = User.create!(hca_id: "ident!next-step", hackatime_access_token: "fake")
    @pet = @user.projects.create!(name: "rock", hackatime_projects: [ "rock-pet" ], tracked_at: Time.current)
  end

  test "past several prizes, the ship step names the one with the most hours" do
    assert_equal "you have the hours for the shirt with every shipped pet. ship to get it reviewed.", ship_detail(11.hours)
    assert_equal "you have the hours for the playground keychain. ship to get it reviewed.", ship_detail(6.hours)
    assert_equal "you have the hours for the stickersheet. ship to get it reviewed.", ship_detail(3.hours)
  end

  test "a prize already redeemed is left out" do
    assert_equal "you have the hours for the playground keychain. ship to get it reviewed.", ship_detail(11.hours, redeemed: %w[shirt])
  end

  test "pending hours on another pet count toward the prize" do
    other = @user.projects.create!(name: "pebble", hackatime_projects: [ "pebble" ])
    other.ships.create!(user: @user, claimed_seconds: 5.hours.to_i)
    assert_equal "you have the hours for the shirt with every shipped pet. ship to get it reviewed.", ship_detail(6.hours)
  end

  private

  def ship_detail(unshipped, redeemed: [])
    @pet.update_columns(tracked_seconds: unshipped.to_i)
    user = User.find(@user.id)
    step = NextStep.for(user, pet: @pet.reload, hours: user.hours, redeemed:)
    assert_equal "ship rock", step.title
    step.detail
  end
end
