# How many browsers reached each section of each guide (GuideSections) on one
# US Eastern day: one row per day, guide, and section, with a count. A
# browser reports each section once, ever (guide_progress_controller.js,
# GuideSectionsController). The table holds nothing about who read.
class GuideSectionDay < ApplicationRecord
  validates :guide, inclusion: { in: GuideSections.keys }

  # One more reader of each section, in one statement, so two reports at
  # once both count.
  def self.count!(guide:, day:, sections:)
    rows = sections.uniq.map { { day:, guide:, section: it, readers: 1 } }
    return if rows.empty?
    upsert_all(rows, unique_by: %i[day guide section], on_duplicate: Arel.sql("readers = guide_section_days.readers + 1"))
  end

  # Each section's readers over the days: { "setup-godot" => 40 }.
  def self.readers(guide, days) = where(guide:, day: days).group(:section).sum(:readers)
end
