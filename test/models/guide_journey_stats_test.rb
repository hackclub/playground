require "test_helper"

# The admin's figures from the journey counts, on nine browsers in the
# desktop's guide, worked out by hand. Each browser is its first touch, the
# index of its furthest stage (0 opened, 1 Set up Godot, 3 Make a GitHub
# Repository, 17 the last), and its time bucket:
#
#   Clubs:  0 at 0m, 1 at 2m, 3 at 5m, 3 at 10m
#   Slack:  1 at 0m, 17 at 60m, 3 at 5m
#   direct: 2 at 2m          (one reader, so it counts as other)
#   other:  1 at 0m          (a value the guard turned into other)
class GuideJourneyStatsTest < ActiveSupport::TestCase
  DAY = Date.new(2026, 10, 8)
  DESKTOP = GuideSections.find("desktop")
  STAGES = GuideJourneyDay.stages(DESKTOP)
  T = TrafficSource::Touch

  setup do
    [ [ "clubs", 0, 0 ], [ "clubs", 1, 2 ], [ "clubs", 3, 5, "slack" ], [ "clubs", 3, 10, "slack" ],
      [ "slack", 1, 0 ], [ "slack", 17, 60 ], [ "slack", 3, 5 ], [ "direct", 2, 2 ], [ "other", 1, 0 ] ].each { browser(*it) }
    # Another guide, and a day outside the days, count nowhere here.
    browser("clubs", 5, 20, guide: GuideSections.find("clubs"))
    browser("clubs", 5, 20, day: DAY - 10)
  end

  test "got this far, stopped here, and their time, for every source" do
    all = stats.all
    assert_equal 9, all.readers
    assert_equal [ 9, 8, 5, 4, 1 ], (0..4).map { all.reached(it) }
    assert_equal [ 1, 3, 1, 3, 0 ], (0..4).map { all.stopped(it) }
    assert_equal 1, all.finished
    assert_equal 1, all.stopped(17), "at the last section, stopping is finishing"
    assert_equal 9, (0..17).sum { all.stopped(it) }
    # Those who stopped at GitHub spent 5m, 10m and 5m: the median is 5m.
    assert_equal 5, all.stopped_minutes(3)
    assert_equal 0, all.stopped_minutes(1)
    assert_nil all.stopped_minutes(4)
    assert_equal [ 3, 2, 2, 1, 0, 0, 1 ], (0..6).map { all.in_bucket(it) }
    assert_equal 2, all.median_minutes
    # Furthest sections 0+1+3+3+1+17+3+2+1 = 31, over 9 readers.
    assert_in_delta 31 / 9.0, all.sections_reached
    # Set up Godot and GitHub tie with 3 stops: the earlier one is marked.
    assert_equal 1, all.biggest_stop
  end

  test "a source with fewer than three readers counts as other, and a picked source is compared with everyone else" do
    assert_equal %w[clubs slack other], stats.sources
    assert_equal [ 4, 3, 2 ], stats.by_source.values.map(&:readers)
    assert_nil stats.chosen

    clubs = stats(source: "clubs")
    assert_equal "clubs", clubs.source
    assert_equal [ 4, 5 ], [ clubs.chosen.readers, clubs.others.readers ]
    assert_equal [ 4, 3, 2, 2, 0 ], (0..4).map { clubs.chosen.reached(it) }
    assert_equal [ 5, 5, 3, 2, 1 ], (0..4).map { clubs.others.reached(it) }
    assert_in_delta 7 / 4.0, clubs.chosen.sections_reached
    # "other" picks every folded source together.
    assert_equal 2, stats(source: "other").chosen.readers
    # A source that is not shown on its own is no choice.
    assert_nil stats(source: "direct").source
  end

  test "last touch groups the same readers by their latest arrival that was not direct" do
    last = stats(touch: "last")
    assert_equal "last", last.touch
    assert_equal %w[slack other], last.sources
    assert_equal [ 5, 4 ], last.by_source.values.map(&:readers)
    assert_equal 9, last.all.readers
    assert_equal "first", stats(touch: "sideways").touch
  end

  test "a forged report can make no figure negative" do
    GuideJourneyDay.count!(guide: DESKTOP, day: DAY, first: touch("clubs"), last: touch("clubs"),
                           from: GuideJourneyDay::Point.new(stage: STAGES[3], minutes: 5), to: GuideJourneyDay::Point.new(stage: STAGES[9], minutes: 40))
    all = stats.all
    assert STAGES.each_index.all? { |i| all.stopped(i) >= 0 && 7.times.all? { |j| all.at(i, j) >= 0 } }
    assert 7.times.all? { all.in_bucket(it) >= 0 }
  end

  test "more stop here only when at least five stopped and the gap passes a test at 95%" do
    group = cohort([ [ 2, 0 ] ] * 10 + [ [ 5, 0 ] ] * 10)
    others = cohort([ [ 2, 0 ] ] * 4 + [ [ 5, 0 ] ] * 36)
    assert GuideJourneyStats.stops_more?(group, others, 2), "10 of 20 against 4 of 40"
    assert_not GuideJourneyStats.stops_more?(others, group, 2), "fewer stop"
    assert_not GuideJourneyStats.stops_more?(cohort([ [ 2, 0 ] ] * 4 + [ [ 5, 0 ] ] * 2), others, 2), "only 4 stopped"
    assert_not GuideJourneyStats.stops_more?(cohort([ [ 2, 0 ] ] * 5 + [ [ 5, 0 ] ] * 15), cohort([ [ 2, 0 ] ] * 3 + [ [ 5, 0 ] ] * 17), 2), "5 of 20 against 3 of 20 is chance"
    assert_not GuideJourneyStats.stops_more?(group, others, STAGES.size - 1), "finishing is not stopping"
  end

  test "time buckets have names" do
    assert_equal [ "under 2m", "2–5m", "5–10m", "10–20m", "20–40m", "40–60m", "60m+" ], GuideJourneyDay::MINUTES.map { GuideJourneyStats.minutes_name(it) }
    assert_nil GuideJourneyStats.minutes_name(nil)
  end

  private

  def stats(**options) = GuideJourneyStats.new(guide: DESKTOP, days: DAY..DAY, **options)
  def touch(source) = T.new(source:, medium: "", campaign: "")

  def browser(first, stage, minutes, last = nil, guide: DESKTOP, day: DAY)
    stage_name = GuideJourneyDay.stages(guide)[stage]
    GuideJourneyDay.count!(guide:, day:, first: touch(first), last: touch(last || first), from: nil,
                           to: GuideJourneyDay::Point.new(stage: stage_name, minutes:))
  end

  # A cohort of browsers, each [furthest stage, time bucket index], built as
  # the counts would hold them.
  def cohort(browsers)
    counts = Hash.new(0)
    browsers.each do |stage, bucket|
      (0..stage).each { |i| (0..bucket).each { |j| counts[[ STAGES[i], GuideJourneyDay::MINUTES[j] ]] += 1 } }
    end
    GuideJourneyStats::Cohort.new(STAGES, [ counts ])
  end
end
