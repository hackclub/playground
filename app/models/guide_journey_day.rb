# How far readers get in each guide (GuideSections) and how long they spend
# on it, by where they came from (TrafficSource), with nothing about who.
#
# A browser keeps its own journey through a guide (guide_progress_controller.js):
# the day it started, its first and last touch then, the furthest stage it
# has reached, and its engaged time, all in localStorage. A stage is
# "opened", then each section in guide order. Time counts in buckets,
# MINUTES, while the tab shows and the reader has done something in the last
# idle_seconds.
#
# The server never holds a journey. A row counts the browsers that started
# the guide on its day, from its sources, and have reached at least its
# stage and at least its minutes. When a browser gets further, or past
# another bucket, it reports where it was and where it is now, and each
# count it newly belongs to goes up by one. Nothing ever goes down, so no
# report can take a count below zero, and a browser counts once whatever
# the days it reads on. GuideJourneyStats turns the counts back into how
# far readers get, where they stop, and how long they spent.
class GuideJourneyDay < ApplicationRecord
  OPENED = "opened"
  MINUTES = [ 0, 2, 5, 10, 20, 40, 60 ].freeze
  # A journey can report its start day for this long. A reader who started
  # more days ago than this stops counting.
  COHORT_DAYS = 120

  # Where a browser is: a stage and a time bucket.
  Point = Data.define(:stage, :minutes)

  # How long a reader can go without scrolling, moving the pointer, touching
  # or typing before the time stops counting, and how long a "minute" lasts.
  # Tests shorten both.
  mattr_accessor :idle_seconds, default: 30
  mattr_accessor :minute_seconds, default: 60

  validates :guide, inclusion: { in: GuideSections.keys }

  def self.stages(guide) = [ OPENED, *guide.sections ]

  # The counts a browser newly belongs to on going from one point to
  # another: each stage up to the new one, with each bucket up to the new
  # one, less those it already belonged to. nil when either point is not one
  # of the guide's, or the new one is behind the old in either way.
  def self.cells(guide, from:, to:)
    stages = stages(guide)
    stage, minutes = stages.index(to.stage), MINUTES.index(to.minutes)
    was_stage, was_minutes = from ? [ stages.index(from.stage), MINUTES.index(from.minutes) ] : [ -1, -1 ]
    return unless stage && minutes && was_stage && was_minutes && was_stage <= stage && was_minutes <= minutes
    (0..stage).flat_map do |i|
      (0..minutes).filter_map { |j| Point.new(stage: stages[i], minutes: MINUTES[j]) unless i <= was_stage && j <= was_minutes }
    end
  end

  # One browser moved from one point to another, or started at to with no
  # from: one more reader in each count it newly belongs to, in one
  # statement, so two reports at once both count. The sources pass the
  # daily cap first (TrafficSource.columns). False if the points do not fit.
  def self.count!(guide:, day:, first:, last:, from:, to:)
    cells = cells(guide, from:, to:)
    return false unless cells
    return true if cells.empty?
    sources = TrafficSource.columns(self, day:, first:, last:)
    rows = cells.map { { day:, guide: guide.key, stage: it.stage, minutes: it.minutes, **sources, readers: 1 } }
    upsert_all(rows, unique_by: :index_guide_journey_days_uniquely, on_duplicate: Arel.sql("readers = guide_journey_days.readers + 1"))
    true
  end
end
