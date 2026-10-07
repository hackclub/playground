# A browser that read Stardance's or the clubs' guide (SideGuide) for
# SideGuide.reading_seconds on a US Eastern day says so here, once that day
# (guide_reading_controller.js): the guide and the day, and nothing else.
# Each says one more reader in GuideReaderDay, which keeps no trace of who.
#
# It answers only for today or yesterday, so a reader just past midnight
# still counts, and a made-up day does not. A burst from one address is cut
# off after RATE requests an hour, enough for a club's room on one network.
# The limit counts by a keyed hash of the address and the day
# (AnonymousCounting), not the address itself, and lasts an hour.
class GuideReadersController < ApplicationController
  include AnonymousCounting

  RATE = 60

  rate_limit to: RATE, within: 1.hour, by: -> { anonymous_key }

  def create
    guide = SideGuide.find(params[:guide])&.slug
    day = asked_day
    return head(:unprocessable_entity) unless guide && day
    GuideReaderDay.count!(guide:, day:)
    head :no_content
  end
end
