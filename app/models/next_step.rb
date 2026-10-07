# The one thing a signed-in participant should do next, at the top of the
# hub: link Hackatime, or link it again, start the guide, redeem a prize the
# approved hours reached, pick the pet's project, ship, wait on the review,
# ship again with new hours, or keep building. Each points at the page that
# does it, or at its part of the guide's step. The pet is the one the guide's
# ship step is about (GuidePet.to_ship). A step about that pet carries it,
# so the card can say which pet it means.
class NextStep < Data.define(:title, :detail, :href, :action, :pet)
  def initialize(title:, detail:, href:, action:, pet: nil) = super
  def self.for(user, pet:, hours:, redeemed:)
    goals = Goal.all.reject { redeemed.include?(it.key) }
    if user.hackatime_unlinked
      new(title: "connect Hackatime again", detail: "Hackatime can't see your account through its link, so your hours can't count.",
          href: GuidePage.href("connect-hackatime"), action: "connect it")
    elsif pet.nil? && !user.hackatime_connected?
      new(title: "start the guide", detail: "install Godot, make your project, and add the Hackatime plugin. then connect Hackatime.",
          href: GuidePage.href("setup-godot"), action: "start with Godot")
    elsif !user.hackatime_connected?
      new(title: "connect Hackatime", detail: "it counts the hours you spend on your pet. it's where the guide adds the plugin.",
          href: GuidePage.href("connect-hackatime"), action: "connect it")
    elsif (goal = goals.find { hours.goal_state(it) == :redeemable }) && user.eligible?
      new(title: "redeem your #{goal.name}", detail: "your approved hours reached #{goal.hours}h.",
          href: Rails.application.routes.url_helpers.new_redemption_path(goal_key: goal.key), action: "redeem")
    elsif pet.nil? || pet.hackatime_projects.empty?
      new(title: "pick your pet's project", detail: "once you've coded the movement in Godot, the guide lists your Hackatime projects.",
          href: GuidePage.href("pick-project"), action: "pick it", pet:)
    elsif goals.any? { hours.goal_state(it) == :ship_to_redeem } && !pet.pending_ship?
      # The prize with the most hours that all the participant's hours so
      # far, approved, pending, and unshipped, would reach once approved.
      goal = goals.select { hours.total_seconds >= it.seconds }.max_by(&:seconds)
      new(title: ship_title(pet), detail: "you have the hours for the #{goal.name}. ship to get it reviewed.",
          href: GuidePage.href("ship"), action: "ship it", pet:)
    elsif pet.pending_ship?
      new(title: "#{pet.name} is in review", detail: "keep building. you can ship again once it's reviewed.",
          href: GuidePage.href("your-own"), action: "keep building", pet:)
    elsif pet.ships.any? && (new_seconds = pet.unshipped_seconds).positive?
      new(title: ship_title(pet), detail: "#{Hours.format(new_seconds)} since its last ship. ship to get them reviewed.",
          href: GuidePage.href("ship"), action: "ship it", pet:)
    else
      goal = goals.find { hours.total_seconds < it.seconds }
      left = goal && Hours.format(goal.seconds - hours.total_seconds)
      new(title: "keep building #{pet.name}", detail: goal ? "#{left} to the #{goal.name}." : "you've passed every goal. ship what's new.",
          href: GuidePage.href("start"), action: "back to the guide", pet:)
    end
  end

  def self.ship_title(pet) = pet.ships.any? ? "ship #{pet.name} again" : "ship #{pet.name}"
end
