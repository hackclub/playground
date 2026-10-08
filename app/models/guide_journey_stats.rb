# How far readers of one guide get, where they stop, and how long they
# spent, by where they came from, for the readers who started it on some
# days (GuideJourneyDay). Sources are first touch or last touch
# (TrafficSource). A source with fewer than TrafficSource.min_shown readers
# in the days is folded into "other".
#
# A count is the readers who reached at least a stage and spent at least a
# number of minutes, so each figure here is a difference of counts:
#
# - got this far: at least the stage, any time.
# - stopped here: got this far, but not to the next stage.
# - time: readers whose engaged time falls in each bucket.
# - stopped here with a time: inclusion and exclusion of the four counts
#   around it. A forged report could make one negative, so each is at
#   least 0.
class GuideJourneyStats
  TOUCHES = %w[first last].freeze
  MINUTES = GuideJourneyDay::MINUTES

  attr_reader :guide, :days, :touch, :source, :stages

  def initialize(guide:, days:, touch: nil, source: nil)
    @guide = guide
    @days = days
    @touch = TOUCHES.include?(touch) ? touch : "first"
    @stages = GuideJourneyDay.stages(guide)
    @counts = Hash.new { |hash, key| hash[key] = Hash.new(0) }
    GuideJourneyDay.where(guide: guide.key, day: days).group(:"#{@touch}_source", :stage, :minutes).sum(:readers).each do |(from, stage, minutes), readers|
      @counts[from][[ stage, minutes ]] += readers
    end
    readers = @counts.transform_values { it[[ GuideJourneyDay::OPENED, 0 ]] }
    shown = readers.select { |from, count| from != TrafficSource::OTHER && count >= TrafficSource.min_shown }
    @members = shown.sort_by { |from, count| [ -count, from ] }.to_h { |from, _| [ from, [ from ] ] }
    rest = readers.keys - @members.keys
    @members[TrafficSource::OTHER] = rest if rest.any?
    @source = source if @members.key?(source)
  end

  # The sources shown, most readers first, then "other".
  def sources = @members.keys

  def all = @all ||= cohort(@counts.keys)
  def chosen = source && (@chosen ||= cohort(@members.fetch(source)))
  def others = source && (@others ||= cohort(@counts.keys - @members.fetch(source)))
  def by_source = @by_source ||= sources.to_h { [ it, cohort(@members.fetch(it)) ] }
  def empty? = all.empty?

  def stage_name(stage) = stage == GuideJourneyDay::OPENED ? "opened the guide" : GuideSections::NAMES.fetch(stage, stage)

  # Whether more of one group of readers stop at stage i than of another,
  # by more than chance would give: at least MIN_STOPS of the first stopped
  # there, and a two-proportion z-test passes at 95%. A section with a
  # couple of readers is never marked.
  MIN_STOPS = 5
  Z_95 = 1.96

  def self.stops_more?(group, others, i)
    return false if i >= group.last
    reached, stopped = group.reached(i), group.stopped(i)
    others_reached, others_stopped = others.reached(i), others.stopped(i)
    return false if stopped < MIN_STOPS || others_reached.zero?
    pooled = (stopped + others_stopped).fdiv(reached + others_reached)
    error = Math.sqrt(pooled * (1 - pooled) * (1.fdiv(reached) + 1.fdiv(others_reached)))
    error.positive? && (stopped.fdiv(reached) - others_stopped.fdiv(others_reached)) / error >= Z_95
  end

  # "2–5m", "60m+", or "under 2m".
  def self.minutes_name(minutes)
    return unless minutes
    after = MINUTES[MINUTES.index(minutes) + 1]
    return "under #{after}m" if minutes.zero?
    after ? "#{minutes}–#{after}m" : "#{minutes}m+"
  end

  private

  def cohort(froms) = Cohort.new(stages, froms.map { @counts[it] })

  # The readers from some sources, as how many reached at least each stage
  # with at least each bucket's minutes: n(i, j).
  class Cohort
    attr_reader :stages

    def initialize(stages, counts)
      @stages = stages
      @n = stages.map { |stage| MINUTES.map { |minutes| counts.sum { it[[ stage, minutes ]] } } }
    end

    def n(stage, bucket) = stage < @n.size && bucket < MINUTES.size ? @n[stage][bucket] : 0

    def readers = n(0, 0)
    def empty? = readers.zero?
    def last = stages.size - 1

    # Readers who got at least as far as stage i.
    def reached(i) = n(i, 0)

    # Readers whose furthest stage is i. At the last stage, those who finished.
    def stopped(i) = [ n(i, 0) - n(i + 1, 0), 0 ].max

    # Readers whose furthest stage is i and whose time is in bucket j.
    def at(i, j) = [ n(i, j) - n(i + 1, j) - n(i, j + 1) + n(i + 1, j + 1), 0 ].max

    # Readers whose time is in bucket j, wherever they stopped.
    def in_bucket(j) = [ n(0, j) - n(0, j + 1), 0 ].max

    # The median time bucket, in minutes, of those who stopped at stage i,
    # or of everyone.
    def stopped_minutes(i) = median(MINUTES.each_index.map { at(i, it) })
    def median_minutes = median(MINUTES.each_index.map { in_bucket(it) })

    # The stage before the last where the most readers stopped.
    def biggest_stop = (0...last).select { stopped(it).positive? }.max_by { [ stopped(it), -it ] }

    # How many sections a reader gets through on average: the mean of each
    # reader's furthest section, counting from 1, with none as 0.
    def sections_reached = empty? ? 0.0 : (1..last).sum { n(it, 0) }.fdiv(readers)

    # Readers who reached the last section.
    def finished = n(last, 0)

    private

    def median(counts)
      total = counts.sum
      return if total.zero?
      seen = 0
      MINUTES[counts.index { (seen += it) * 2 >= total }]
    end
  end
end
