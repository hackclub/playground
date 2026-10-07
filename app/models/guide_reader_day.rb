# How many browsers read a side guide (SideGuide) for SideGuide.reading_seconds
# or more on one US Eastern day: one row per day and guide, with a count.
# A browser keeps its own reading time and tells the server once a day
# (guide_reading_controller.js, GuideReadersController). The table holds
# nothing about who read.
class GuideReaderDay < ApplicationRecord
  validates :guide, inclusion: { in: SideGuide.slugs }

  # One more reader of the guide on the day, in one statement, so two at
  # once both count.
  def self.count!(guide:, day:)
    upsert({ day:, guide:, readers: 1 }, unique_by: %i[day guide], on_duplicate: Arel.sql("readers = guide_reader_days.readers + 1"))
  end

  # The readers on each of the days, by guide: { date => { "stardance" => 12 } }.
  # A day or guide with none is absent.
  def self.per_day(days)
    where(day: days).pluck(:day, :guide, :readers).each_with_object({}) { |(day, guide, readers), all| (all[day] ||= {})[guide] = readers }
  end
end
