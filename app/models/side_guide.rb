# The guide in steps for readers who come from Stardance or from a Hack Club
# club, at /stardance and /clubs (SideGuidesController). Neither ships to
# playground, so neither guide has anything that needs an account: no sign
# in, no Hackatime link, no pick of the pet's project, no Ship it, and
# nothing beside the guide but its outline. Anyone can read them, signed in
# or not, with the new site or not.
#
# Stardance counts Hackatime time, so its guide keeps the steps that set up
# Hackatime in Godot. A club needs no Hackatime, so its guide leaves
# Hackatime out.
class SideGuide < Data.define(:slug, :name, :hackatime)
  # A reader who spends this long on a guide in one US Eastern day counts as
  # active that day (GuideReaderDay). Tests shorten it.
  cattr_accessor :reading_seconds, default: 20 * 60

  # The cookie that remembers which one this browser opened last, so /
  # sends it back there. It holds the guide's slug and nothing else.
  COOKIE = :guide_origin

  ALL = [
    new(slug: "stardance", name: "Stardance", hackatime: true),
    new(slug: "clubs", name: "Clubs", hackatime: false)
  ].freeze

  def self.all = ALL
  def self.slugs = ALL.map(&:slug)
  def self.find(slug) = ALL.find { it.slug == slug.to_s }

  def to_param = slug
end
