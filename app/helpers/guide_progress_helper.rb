# The tracker of how far a reader reads a guide (GuideSections,
# guide_progress_controller.js), on the guides' pages alone. It is not in the
# import map, so no other page lists or loads it.
module GuideProgressHelper
  # Registers the tracker. A guide's page puts it in its head.
  def guide_progress_tag
    path = asset_path("guide/guide_progress_controller.js")
    script = [ %(import { application } from "controllers/application"), "import tracker from #{json_escape(path.to_json)}",
               %(application.register("guide-progress", tracker)) ].join("\n")
    tag.script(script.html_safe, type: "module")
  end

  # The data attributes for the element the tracker watches, for one guide.
  def guide_progress_data(key)
    guide = GuideSections.find(key)
    { guide_progress_guide_value: guide.key, guide_progress_sections_value: guide.sections.to_json,
      guide_progress_seconds_value: GuideSections.reach_seconds, guide_progress_every_value: GuideSections.send_seconds,
      guide_progress_url_value: guide_sections_path }
  end
end
