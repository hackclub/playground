# A browser reading one of the guides (GuideSections) reports its journey
# through it as it moves on (guide_progress_controller.js): the guide, the
# day it started, its first and last touch then (TrafficSource), where it
# was, and where it is now, as a stage and a time bucket. Each count the
# browser newly belongs to goes up by one (GuideJourneyDay), which keeps no
# trace of who. A report never takes a count down.
#
# Only a guide's own stages and the buckets count, moving forward, for a
# start day the browser could have. Sources pass the cardinality guard. A
# browser reports a few dozen times a guide at most, so the limit matches
# the section reports': a burst from one address is cut off after RATE an
# hour, room for a club reading on one network. The request is not logged
# (config/application.rb), so no log line pairs an address with a report.
class GuideJourneysController < ApplicationController
  include AnonymousCounting

  RATE = 300

  rate_limit to: RATE, within: 1.hour, by: -> { anonymous_key }

  def create
    guide = GuideSections.find(params[:guide])
    day = journey_day
    to = point(:to)
    # A first report says where the browser is, and no more.
    moved = params[:from_stage].present? || params[:from_minutes].present?
    from = point(:from) if moved
    return head(:unprocessable_entity) unless guide && day && to && (from || !moved)
    sources = params.slice(*TrafficSource::COLUMNS).permit(*TrafficSource::COLUMNS)
    counted = GuideJourneyDay.count!(guide:, day:, **TrafficSource.touches(sources), from:, to:)
    head(counted ? :no_content : :unprocessable_entity)
  end

  private

  def point(prefix)
    stage, minutes = params[:"#{prefix}_stage"], params[:"#{prefix}_minutes"]
    return unless stage.is_a?(String) && minutes.is_a?(String) && minutes.match?(/\A\d{1,2}\z/)
    GuideJourneyDay::Point.new(stage:, minutes: minutes.to_i)
  end
end
