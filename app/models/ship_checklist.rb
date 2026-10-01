# The list in the ship popup: each check that blocks shipping or warns, with
# the one field that fixes it there, when there is one. The two description
# checks share one field, and one step with one name, the stricter one's. A
# step fixed while the popup is open stays in the list, ticked, so its field
# stays too. The next opening lists only what is left.
#
# A step that can't be done yet waits off the list until the step it needs
# passes: the README and the commits need the repository, and new hours need
# a Hackatime project. Only the list waits. Shipping still needs every check.
#
# A step's label says what to do. A step that could be unclear also has a tip,
# which says why, or where to go. A check that could not run says so in its
# tip instead.
class ShipChecklist
  FIELDS = { description: :description, description_length: :description, repo: :code_url,
             playable: :playable_url, hackatime_projects: :hackatime_projects, screenshot: :screenshot,
             ship_message: :ship_message_url }.freeze
  NEEDS = { readme: :repo, commits: :repo, new_hours: :hackatime_projects }.freeze
  TIPS = {
    eligible: "verify your identity at auth.hackclub.com, then open this again.",
    not_banned: "if you think this is a mistake, ask in #playground.",
    hackatime_link: "Hackatime isn't letting playground see your account through this link, so your hours can't count. link it again to fix it.",
    trust: "Hackatime has banned this account, so its hours can't count.",
    new_hours: "you can only ship a pet if you've tracked hours with Hackatime or Lapse since your last ship. " \
               "maybe connect another Hackatime project, or track some more hours?",
    repo: "a public link where anyone can read your pet's code. on GitHub, the repository needs to be public.",
    playable: "where people get your pet: a GitHub release with an installer or executable, not only the source code, " \
              "or a website that loads for anyone.",
    ship_message: "each ship needs its own post in #playground-ships. once you've posted, open the message's more actions " \
                  "menu, choose copy link, and paste it here.",
    playable_host: "itch.io is best, since that's where people find pets. another link is fine if someone can play or run your pet from it.",
    commits: "this doesn't stop you shipping. committing as you go shows how your pet came together."
  }.freeze
  UNCHECKED_TIP = "we couldn't check this just now. try again in a minute.".freeze

  Item = Data.define(:key, :label, :tip, :ok, :blocker, :field)

  attr_reader :gate

  # shown: the keys of the items the open popup lists now.
  def initialize(project, shown: [])
    @project = project
    @gate = SubmitGate.new(project)
    @shown = Array(shown).map(&:to_s)
  end

  def items
    @items ||= gate.checks.group_by { (FIELDS[it.key] || it.key).to_s }.filter_map do |key, checks|
      next if checks.any? { waiting?(it) }
      failing = checks.find(&:failed?)
      next unless failing || @shown.include?(key)
      check = failing || checks.last
      Item.new(key:, label: checks.last.label, tip: tip(check), ok: failing.nil?, blocker: check.blocker?, field: FIELDS[check.key])
    end
  end

  def passed? = gate.passed?

  private

  def waiting?(check) = NEEDS.key?(check.key) && gate.checks.find { it.key == NEEDS[check.key] }.failed?

  def tip(check)
    return UNCHECKED_TIP if check.detail.to_s.start_with?(SubmitGate::UNCHECKED)
    TIPS[check.key]
  end
end
