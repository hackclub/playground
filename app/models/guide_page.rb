# The guide in steps, one at a time, each at an address of its own, such as
# /guide/move. /guide shows the first. Buttons under the guide go to the step
# before and the step after.
#
# Each step lists the anchors on its page. A link from when the guide was one
# long page, such as /guide#movement in an email, goes on to the step that
# holds its anchor (guides/_old_links.html.erb). So does a login begun at a
# step that acts on the site, and the next step card's link.
class GuidePage < Data.define(:slug, :name, :anchors)
  def self.all = STEPS
  def self.first = STEPS.first
  def self.find(slug) = STEPS.find { it.slug == slug }
  def self.holding(anchor) = STEPS.find { it.anchors.include?(anchor) }

  # A link to an anchor on the step that holds it: /guide/move#pick-project.
  def self.href(anchor) = "#{holding(anchor).path}##{anchor}"

  # Every anchor and the address of the step that holds it.
  def self.anchor_paths = STEPS.flat_map { |step| step.anchors.map { [ it, step.path ] } }.to_h

  # Where a login or a Hackatime link begun at a step goes back to: that
  # step, at that anchor. A way back from before the steps, /guide#<anchor>,
  # goes to the step that holds the anchor, or to /guide when no step does.
  # Any other address gives nil, so it cannot steer a login.
  def self.way_back(value)
    slug, anchor = value.to_s.match(%r{\A/guide(?:/([a-z]{1,20}))?#([a-z0-9-]{1,40})\z})&.captures
    return unless anchor
    return (holding(anchor) ? href(anchor) : "/guide##{anchor}") unless slug
    "#{find(slug).path}##{anchor}" if find(slug)
  end

  def number = STEPS.index(self) + 1
  def previous = (STEPS[number - 2] if number > 1)
  def following = STEPS[number]
  def to_param = slug
  def path = Rails.application.routes.url_helpers.guide_page_path(self)

  STEPS = [
    new(slug: "setup", name: "Set up",
        anchors: %w[sign-in-title sign-in setup-godot hackatime connect-hackatime hackatime-step github sync commands in-godot in-the-terminal]),
    new(slug: "scene", name: "Build the scene", anchors: %w[start transparent]),
    new(slug: "art", name: "Art and script", anchors: %w[pretty script]),
    new(slug: "move", name: "Make it move", anchors: %w[movement pick-project pick-step on-screen bounce]),
    new(slug: "animate", name: "Animate and drag", anchors: %w[animations break drag]),
    new(slug: "publish", name: "Publish and ship", anchors: %w[your-own publish it-s-time-to-upload-your-project-to-itch ship ship-step])
  ].freeze
end
