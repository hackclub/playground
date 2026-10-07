# The one thing a signed-in participant should do next, at the top of the
# hub: link Hackatime, or link it again, start the guide, redeem a prize the
# approved hours reached, pick the pet's project, link the pet to Hackatime,
# ship, wait on the review, ship again with new hours, or keep building.
# Each points at the page that does it, or at its part of the guide's step,
# and a link into the guide says where it goes. The pet is the one the
# guide's ship step is about (GuidePet.to_ship). A step about that pet
# carries it, so the card can say which pet it means.
#
# The server knows the account, not how far the reader has read, which the
# browser keeps (guide_place_controller.js). So a step that comes from
# reading, not from the account, carries progress: the card's script
# (next_step_controller.js) moves its link on to the furthest step read,
# never back, with progress's title and detail in place of the card's. And
# a step can carry later: what the card says instead once the reader has
# read past the part later points to without doing it.
class NextStep < Data.define(:title, :detail, :href, :action, :pet, :progress, :later)
  # The parts of the guide the card links to, by anchor, as their headings
  # name them.
  SECTIONS = { "setup-godot" => "Set up Godot", "pick-project" => "Pick your pet's project", "ship" => "Ship it",
               "your-own" => "Make it your own!" }.freeze

  def initialize(title:, detail:, href:, action:, pet: nil, progress: nil, later: nil) = super

  def self.for(user, pet:, hours:, redeemed:)
    goals = Goal.all.reject { redeemed.include?(it.key) }
    if user.hackatime_unlinked
      new(title: "connect Hackatime again", detail: "Hackatime can't see your account through its link, so your hours can't count.", **go_to("pick-project"))
    elsif pet.nil? && !user.hackatime_connected?
      new(title: "start the guide", detail: "install Godot, make your project, and add the Hackatime plugin.", **go_to("setup-godot"),
          progress: { title: "continue the guide", detail: "pick up where you left off." },
          later: { title: "connect Hackatime", detail: "connect it and pick your pet's project, at the end of Build the scene, so your hours count.",
                   **go_to("pick-project") })
    elsif !user.hackatime_connected?
      new(title: "connect Hackatime", detail: "connect it and pick #{pet.name}'s project, so the hours you spend on it count.", **go_to("pick-project"), pet:)
    elsif (goal = goals.find { hours.goal_state(it) == :redeemable }) && user.eligible?
      new(title: "redeem your #{goal.name}", detail: "your approved hours reached #{goal.hours}h.",
          href: Rails.application.routes.url_helpers.new_redemption_path(goal_key: goal.key), action: "redeem")
    elsif pet.nil?
      new(title: "pick your pet's project", detail: "once you've built the scene in Godot, the guide lists your Hackatime projects.", **go_to("pick-project"))
    elsif unlinked?(pet)
      new(title: "link #{pet.name} to Hackatime", detail: "Hackatime counts no time on #{pet.name} yet. pick the project Godot sends its time to, so its hours count.",
          **go_to("pick-project"), pet:)
    elsif goals.any? { hours.goal_state(it) == :ship_to_redeem } && !pet.pending_ship?
      # The prize with the most hours that all the participant's hours so
      # far, approved, pending, and unshipped, would reach once approved.
      goal = goals.select { hours.total_seconds >= it.seconds }.max_by(&:seconds)
      new(title: ship_title(pet), detail: "you have the hours for the #{goal.name}. ship to get it reviewed.", **go_to("ship"), pet:)
    elsif pet.pending_ship?
      new(title: "#{pet.name} is in review", detail: "keep building. you can ship again once it's reviewed.", **go_to("your-own"), pet:)
    elsif pet.ships.any? && (new_seconds = pet.unshipped_seconds).positive?
      new(title: ship_title(pet), detail: "#{Hours.format(new_seconds)} since its last ship. ship to get them reviewed.", **go_to("ship"), pet:)
    else
      goal = goals.find { hours.total_seconds < it.seconds }
      left = goal && Hours.format(goal.seconds - hours.total_seconds)
      # The pet's project is picked at the end of its step, so the guide goes
      # on from the step after, or from further on, as far as this browser read.
      on = GuidePage.holding("pick-project").following
      title = "keep building #{pet.name}"
      new(title:, detail: goal ? "#{left} to the #{goal.name}." : "you've passed every goal. ship what's new.",
          href: on.path, action: "continue: #{on.name}", pet:, progress: { title: })
    end
  end

  def self.ship_title(pet) = pet.ships.any? ? "ship #{pet.name} again" : "ship #{pet.name}"

  # A pet whose hours do not count: it names no Hackatime project, or its
  # projects have no time in the program window and it never shipped.
  def self.unlinked?(pet) = pet.hackatime_projects.empty? || (pet.tracked_seconds.to_i.zero? && pet.ships.none?)

  def self.go_to(anchor) = { href: GuidePage.href(anchor), action: "go to: #{SECTIONS.fetch(anchor)}" }
end
