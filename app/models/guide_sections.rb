# The guides whose readers' progress is counted, and each one's sections in
# the order the guide reads: the desktop's one long guide at /guide, the new
# site's guide in steps, Stardance's, and the clubs' (SideGuide). A section
# is a heading, named by its anchor, as GuidePage and the outline name it.
# A browser reports each section it reached once, ever, and the server
# counts reports per day (GuideSectionDay), so the admin stats show where
# readers stop. Nothing names the reader.
#
# A section is reached when its heading stays in the top two thirds of the
# screen for reach_seconds while the tab shows, or, at the very end of the
# page, anywhere on screen (guide_progress_controller.js). A fast scroll past
# it does not count.
module GuideSections
  Guide = Data.define(:key, :name, :sections)

  # The headings' names, for the admin stats.
  NAMES = {
    "setup-godot" => "Set up Godot", "hackatime" => "Install Godot Hackatime", "github" => "Make a GitHub Repository",
    "sync" => "Sync with GitHub", "commands" => "Important commands", "in-godot" => "In Godot", "in-the-terminal" => "In the terminal",
    "start" => "Start making the pet", "transparent" => "Make the scene transparent", "pick-project" => "Pick your pet's project",
    "pretty" => "Making it pretty", "script" => "Add the functionality", "movement" => "Movement", "on-screen" => "Keep it on screen",
    "bounce" => "Bounce off the edges", "animations" => "Animations", "break" => "Let it take a break",
    "drag" => "Pick it up and drag it around", "your-own" => "Make it your own", "publish" => "Export it and put it on itch.io",
    "it-s-time-to-upload-your-project-to-itch" => "Upload it to itch.io", "ship" => "Ship it"
  }.freeze

  # The new site's guide, in steps. Its sign in shows only to a visitor,
  # who cannot read on without signing in, so it is not a section.
  STEPS = %w[setup-godot hackatime github sync commands in-godot in-the-terminal start transparent pick-project pretty script
             movement on-screen bounce animations break drag your-own publish it-s-time-to-upload-your-project-to-itch ship].freeze

  ALL = [
    # The one long guide names fewer headings, and none that act on the site.
    Guide.new(key: "desktop", name: "the desktop's guide",
              sections: %w[setup-godot hackatime github sync commands start transparent pretty script movement on-screen bounce
                           animations break drag your-own publish].freeze),
    Guide.new(key: "new_site", name: "the new site's guide", sections: STEPS),
    # The side guides have no pick step and no Ship it, and the clubs' no Hackatime.
    Guide.new(key: "stardance", name: "Stardance's guide", sections: (STEPS - %w[pick-project ship]).freeze),
    Guide.new(key: "clubs", name: "the clubs' guide", sections: (STEPS - %w[pick-project ship hackatime]).freeze)
  ].freeze

  # How long a heading stays in view to count, and how often a page sends
  # what it reached. Tests shorten both.
  mattr_accessor :reach_seconds, default: 2
  mattr_accessor :send_seconds, default: 15

  def self.all = ALL
  def self.keys = ALL.map(&:key)
  def self.find(key) = ALL.find { it.key == key.to_s }
end
