# The NPS on the admin stats page: how likely participants are to recommend
# playground, from their answers in nps.exe and at ship. NPS is the share of
# promoters, who answer 9 or 10, minus the share of detractors, who answer 0
# to 6, as a whole number from -100 to 100. Passives, 7 or 8, count only
# toward the people. Over a span of days each person counts once, by their
# latest answer in it. Days are US Eastern. Admins' answers are left out, as
# in ProgramStats.
class NpsStats
  # The answers in the 7 days ending on last_day, each person's latest.
  Span = Data.define(:last_day, :promoters, :passives, :detractors) do
    def people = promoters + passives + detractors
    def nps = people.zero? ? nil : (100.0 * (promoters - detractors) / people).round
  end
  Answer = Data.define(:user_id, :score, :at, :id) do
    def day = NpsResponse.day(at)
  end

  DAYS = 7
  LATEST = 30

  attr_reader :now

  def initialize(now: Time.current)
    @now = now
    @answers = participants_answers.pluck(:user_id, :score, :created_at, :id).map { Answer.new(*it) }
  end

  def any? = @answers.any?

  # The 7 days ending today, today so far included.
  def last_7_days = span(today)

  # One span per Eastern day, from the first answer's day to today, oldest
  # first.
  def over_time
    return [] if @answers.empty?
    (@answers.map(&:day).min..today).map { span(it) }
  end

  # The newest answers, with their people and pets.
  def latest = participants_answers.includes(:user, :project).order(created_at: :desc, id: :desc).limit(LATEST)

  def span(last_day)
    days = (last_day - (DAYS - 1))..last_day
    latest = @answers.select { days.cover?(it.day) && it.at <= @now }.group_by(&:user_id).values.map { it.max_by { [ it.at, it.id ] } }
    Span.new(last_day:, promoters: latest.count { NpsResponse::PROMOTERS.cover?(it.score) },
             passives: latest.count { NpsResponse::PASSIVES.cover?(it.score) }, detractors: latest.count { NpsResponse::DETRACTORS.cover?(it.score) })
  end

  private

  def today = NpsResponse.day(@now)
  def participants_answers = NpsResponse.where(user: User.where(admin: false))
end
