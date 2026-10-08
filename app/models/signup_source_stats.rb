# Where new accounts came from over some days (SignupSourceDay), by first
# touch or last touch (TrafficSource): each source's signups and share,
# most first, and the campaigns that brought any. A source or campaign with
# fewer than TrafficSource.min_shown signups in the days is folded into
# "other", so a glance at a day's few signups names nobody's source.
class SignupSourceStats
  Row = Data.define(:name, :signups, :share)

  attr_reader :days, :touch

  def initialize(days:, touch: nil)
    @days = days
    @touch = GuideJourneyStats::TOUCHES.include?(touch) ? touch : "first"
    scope = SignupSourceDay.where(day: days)
    @total = scope.sum(:signups)
    @sources = rows(scope.group(:"#{@touch}_source").sum(:signups))
    @campaigns = rows(scope.where.not("#{@touch}_campaign": "").group(:"#{@touch}_campaign").sum(:signups))
  end

  attr_reader :total, :sources, :campaigns

  def empty? = total.zero?

  # The first day any signup was counted, which is when counting began.
  def self.started = SignupSourceDay.minimum(:day)

  private

  def rows(counts)
    shown, rest = counts.partition { |name, count| name != TrafficSource::OTHER && count >= TrafficSource.min_shown }
    rows = shown.sort_by { |name, count| [ -count, name ] }.map { |name, count| Row.new(name:, signups: count, share: count.fdiv(@total)) }
    other = rest.sum(&:last)
    other.positive? ? rows << Row.new(name: TrafficSource::OTHER, signups: other, share: other.fdiv(@total)) : rows
  end
end
