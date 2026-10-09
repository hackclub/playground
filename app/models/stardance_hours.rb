# The hours of Stardance's playground mission in each stage, as the last
# read of Stardance's database left them (StardanceStages). One row, its
# updated_at the time of that read. returned_seconds are part of
# unshipped_seconds: those of projects sent back for changes. The projects
# and seconds left out are of projects that are also pets here, counted in
# this site's stages instead.
class StardanceHours < ApplicationRecord
  self.table_name = "stardance_hours"

  STAGES = %i[approved pending unshipped].freeze

  # The latest read, or nil before the first.
  def self.latest = order(:updated_at).last

  # Replaces the row with the totals (StardanceStages::Totals).
  def self.record!(totals)
    transaction do
      delete_all
      create!(approved_seconds: totals.approved, pending_seconds: totals.pending, unshipped_seconds: totals.unshipped,
              returned_seconds: totals.returned, projects: totals.projects,
              left_out_projects: totals.left_out_projects, left_out_seconds: totals.left_out_seconds)
    end
  end

  # { approved:, pending:, unshipped: } in seconds, as ProgramStats#hours_by_stage.
  def by_stage = STAGES.index_with { public_send(:"#{it}_seconds") }

  def total_seconds = by_stage.values.sum
end
