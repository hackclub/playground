# A browser reading one of the guides (GuideSections) reports the sections it
# reached since it last reported, each once, ever
# (guide_progress_controller.js): the guide, the day, and the sections, and
# nothing else. Each adds one reader to that day's count for its section in
# GuideSectionDay, which keeps no trace of who.
#
# Only a guide and sections that guide has count, for today or yesterday. A
# browser reports a few times as it reads, so the limit is wider than the
# readers' count's: a burst from one address is cut off after RATE reports
# an hour, room for a club reading on one network.
class GuideSectionsController < ApplicationController
  include AnonymousCounting

  RATE = 300

  rate_limit to: RATE, within: 1.hour, by: -> { anonymous_key }

  def create
    guide = GuideSections.find(params[:guide])
    sections = Array(params[:sections]).map(&:to_s) & guide.sections if guide
    day = asked_day
    return head(:unprocessable_entity) unless guide && day && sections.present?
    GuideSectionDay.count!(guide: guide.key, day:, sections:)
    head :no_content
  end
end
