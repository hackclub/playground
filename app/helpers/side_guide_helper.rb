# The guide in steps shows in two kinds of place: on the new site, at /guide,
# and as a side guide for Stardance or for clubs, at /stardance and /clubs
# (SideGuide), where it has nothing that needs an account. Its partials ask
# these, so the new site's guide stays as it is.
module SideGuideHelper
  # The side guide this page is, or nil on the new site's guide.
  def side_guide = @side_guide

  # A step's address on the guide this page is.
  def guide_step_path(step) = side_guide ? side_guide_path(side_guide, step) : guide_page_path(step)

  # A step's name. A side guide's last step has no Ship it, so it is Publish.
  def guide_step_name(step) = side_guide && step == GuidePage.all.last ? "Publish" : step.name

  # Whether the guide sets up Hackatime in Godot: the new site's and
  # Stardance's do, and a club's has no Hackatime.
  def guide_hackatime? = !side_guide || side_guide.hackatime

  # Where this browser keeps its place in this guide (guide_place_controller.js),
  # one key a guide, so the new site's guide and each side guide keep their own.
  def guide_place_key = "playground-guide-place:#{side_guide&.slug || "guide"}"

  # Each step as the browser's scripts read it: [slug, name, address].
  def guide_steps_for_scripts = GuidePage.all.map { [ it.slug, guide_step_name(it), guide_step_path(it) ] }
end
