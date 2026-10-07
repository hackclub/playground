# What the hub shows beside the guide for a signed-in participant: their
# hours, redemptions, the guide's pet, and the next step. The next step is
# about the pet the guide's ship step is about, so after a ship it follows
# that pet into its review. Both start from the pet the participant set
# active, if any. The hub's page and its side frame, which reloads when a
# guide step is done or the active pet changes, both read it.
class Hub
  attr_reader :hours, :redemptions, :pet, :next_step

  def initialize(user, active_pet_id = nil)
    TrackedTime.refresh_all(user)
    @hours = user.hours
    @redemptions = user.redemptions.index_by(&:goal_key)
    @pet = GuidePet.for(user, active_pet_id)
    @next_step = NextStep.for(user, pet: @pet || GuidePet.shipped_last(user), hours: @hours, redeemed: @redemptions.keys)
  end
end
