# Every hour, reads the hours of Stardance's playground mission by stage
# (StardanceStages) and keeps the totals (StardanceHours) for the admin
# stats pie, so the page never waits on Stardance. A project that is also a
# pet here is left out, as this site's stages count it.
#
# Without a Stardance MCP token it does nothing. When the read fails, the
# last totals stay, and their time shows how old they are.
class StardanceHoursJob < ApplicationJob
  queue_as :default

  def perform
    return unless StardanceMcp.configured?
    StardanceHours.record!(StardanceStages.sum(StardanceStages.fetch, here: StardanceStages.here))
  rescue StardanceMcp::Rejected => e
    Rails.logger.error(e.message)
  rescue => e
    Rails.logger.error("Stardance hours not read (#{e.class})")
  end
end
