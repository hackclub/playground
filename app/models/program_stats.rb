# The numbers behind the admin stats page. Each section answers one question
# an organizer acts on: where hours stand, where people stop, who to nudge,
# and when people code. Every participant (everyone but admins) is loaded
# once, with their pets, ships, and redemptions, and coding hours are summed
# in SQL, so the page takes the same few queries however many people there
# are.
#
# A count of people is a Group. The people page filters by a group's key, so
# a count links to exactly the people it counts.
class ProgramStats
  Group = Data.define(:key, :label, :ids) do
    def count = ids.size
  end

  # A participant and everything of theirs the stats read.
  Person = Data.define(:user, :projects, :ships, :redemptions, :hours) do
    def id = user.id
  end

  Step = Data.define(:key, :label, :reached, :stuck, :share, :biggest_drop)
  Waiting = Data.define(:count, :oldest, :seconds)
  Review = Data.define(:review_queue, :fraud_queue, :to_review, :to_fraud, :reviewed, :sent_back, :shipped_again, :claimed, :approved)
  Cut = Data.define(:deflated, :deducted, :rejected) do
    def total = deflated + deducted + rejected
  end
  Refreshes = Data.define(:pets, :oldest, :median, :never)
  Bucket = Data.define(:from, :to, :label, :goal, :group)
  GoalRow = Data.define(:goal, :total, :approved, :redeemed, :fulfilled)
  PetCondition = Data.define(:key, :label, :pets, :owners)
  Pets = Data.define(:count, :seconds, :conditions, :ready_pets, :ready)
  Day = Data.define(:date, :group)
  Signups = Data.define(:days, :before)
  # A day of the window. A day after today has no figures yet.
  CodingDay = Data.define(:date, :seconds, :people, :signups, :counted)
  # A day so far and who was active on it, most time first, with how many
  # came from each side guide by guide: { "stardance" => 12 }. They have no
  # account here, so they are a count, not people. Stardance's count is of
  # the people on its playground mission with Hackatime time that day
  # (StardanceActiveDay), and stardance is that day's row. A day without
  # one, as before the job first ran, falls back to the browsers that read
  # Stardance's guide long enough (GuideReaderDay), as the clubs' count
  # always is.
  ActiveDay = Data.define(:date, :people, :today, :readers, :stardance) do
    def count = people.size
    def reader_count = readers.values.sum
    def total = count + reader_count
  end
  # A participant active on a day, and why: seconds by kind of activity,
  # as { coded: 1200 }. Hackatime time is the only kind so far. Another
  # kind adds its own key.
  Active = Data.define(:user, :reasons) do
    def seconds = reasons.values.sum
  end
  Fetches = Data.define(:linked, :oldest, :median, :never)
  Momentum = Data.define(:last_7_days, :previous_7_days, :span, :coded, :projected, :to_first_code)

  # A participant is active on an Eastern day with at least this much
  # Hackatime time that day, summed over the day's hours.
  ACTIVE_CODING_SECONDS = 60

  # What each offline ship check asks of a pet, for the unshipped pets table.
  PET_CONDITIONS = {
    eligible: "owner verified and eligible", description: "a description",
    description_length: "a description of #{SubmitGate::MIN_DESCRIPTION} or more characters",
    hackatime_projects: "a Hackatime project", repo: "a code link", playable: "a playable link", screenshot: "a screenshot"
  }.freeze

  # Columns the stats never read. Tokens stay encrypted in the database, and
  # ship snapshots and notes are large.
  SECRET_USER_COLUMNS = %w[hca_access_token hca_refresh_token hackatime_access_token].freeze
  SHIP_TEXT_COLUMNS = %w[snapshot review_checklist review_judgement review_feedback fraud_notes].freeze

  attr_reader :now

  def initialize(now: Time.current)
    @now = now
    @groups = {}
    participants = User.where(admin: false)
    @coding = CodingHour.where(user: participants)
    users = participants.select(*(User.column_names - SECRET_USER_COLUMNS), "hackatime_access_token IS NOT NULL AS hackatime_linked")
                        .preload(:projects).to_a
    ships = Ship.where(user: participants).select(*(Ship.column_names - SHIP_TEXT_COLUMNS)).order(:created_at).group_by(&:user_id)
    redemptions = Redemption.where(user: participants).select(:id, :user_id, :goal_key, :status).group_by(&:user_id)
    @people = users.map do |user|
      own = ships.fetch(user.id, [])
      Person.new(user:, projects: user.projects.to_a, ships: own, redemptions: redemptions.fetch(user.id, []),
                 hours: Hours.new(user, ships: own, projects: user.projects))
    end
  end

  # The group a people page filter names, or nil for a key no section makes.
  # Each section records its groups as it is built.
  def group_for(key) = (@all_groups ||= [ funnel, nudges, histogram, goals, pets, signups, coders ].then { @groups })[key.to_s]

  # a. Every participant's hours by stage, as the meter counts them.
  def hours_by_stage
    @hours_by_stage ||= %i[approved pending unshipped].index_with do |stage|
      @people.sum { it.hours.public_send(:"#{stage}_seconds") }
    end
  end

  # Claimed hours that finished ships did not approve: deflated in review,
  # deducted in fraud, and whole claims rejected.
  def cut
    approved = finished_ships.select(&:approved?)
    Cut.new(deflated: approved.sum(&:deflated_seconds), deducted: approved.sum(&:fraud_deduction_seconds),
            rejected: finished_ships.select(&:rejected?).sum(&:claimed_seconds))
  end

  # Unshipped hours are as of each pet's last Hackatime refresh, which runs
  # when its owner opens their dashboard.
  def refreshes
    pets = @people.flat_map(&:projects).select { it.hackatime_projects.any? }
    ages = pets.filter_map { @now - it.tracked_at if it.tracked_at }
    Refreshes.new(pets: pets.size, oldest: ages.max, median: median(ages), never: pets.count { it.tracked_at.nil? })
  end

  # b. Each step counts the people who passed it and every step before, so
  # "stuck" at a step means passed the one before and not this one.
  def funnel
    @funnel ||= begin
      first = Goal.all.first
      tests = {
        signed_up: [ "signed up", ->(_) { true } ],
        eligible: [ "verified and eligible", ->(p) { p.user.eligible? } ],
        hackatime: [ "Hackatime linked", ->(p) { p.user.hackatime_linked } ],
        pet: [ "made a pet", ->(p) { p.projects.any? } ],
        # A ship took its time from a linked project, so it counts too, even
        # if the project was unlinked after.
        linked: [ "linked a Hackatime project to a pet", ->(p) { p.projects.any? { it.hackatime_projects.any? } || p.ships.any? } ],
        tracked: [ "any tracked time", ->(p) { p.projects.any? { it.tracked_seconds.positive? } || p.ships.any? { it.claimed_seconds.positive? } } ],
        first_goal: [ "#{first.hours}h in total, the first goal", ->(p) { p.hours.total_seconds >= first.seconds } ],
        shipped: [ "shipped", ->(p) { p.ships.any? } ],
        approved: [ "a ship approved", ->(p) { p.ships.any?(&:approved?) } ],
        redeemed: [ "redeemed a goal", ->(p) { p.redemptions.any? } ],
        fulfilled: [ "a redemption fulfilled", ->(p) { p.redemptions.any? { it.status == "fulfilled" } } ]
      }
      passed = @people
      before = nil
      steps = tests.map do |key, (label, test)|
        reached = passed.select(&test)
        stuck = collect("stuck_#{key}", "passed “#{before.label}” but not “#{label}”", passed.reject(&test)) if before
        before = Step.new(key:, label:, stuck:, biggest_drop: false, share: before && fraction(reached.size, passed.size),
                          reached: collect("reached_#{key}", "passed every step up to “#{label}”", reached))
        passed = reached
        before
      end
      biggest = steps.drop(1).max_by { it.stuck.count }
      steps.map { it.with(biggest_drop: it.equal?(biggest) && biggest.stuck.count.positive?) }
    end
  end

  # c. People one message could move on. Banned people are left out.
  def nudges
    @nudges ||= begin
      active = @people.reject { it.user.banned? }
      [
        collect("ship_now", "enough hours for their next goal, and nothing in review", active.select { should_ship?(it) }),
        collect("no_hackatime", "signed up over a day ago, no Hackatime linked",
              active.select { !it.user.hackatime_linked && it.user.created_at < @now - 1.day }),
        collect("redeem_now", "approved hours reach a goal they haven't redeemed", active.select { redeemable(it).any? }),
        collect("changes_back", "a ship sent back for changes, with no newer ship", active.select { sent_back_pets(it).any? }),
        collect("went_quiet", "coded before, but not in the last 3 days",
                active.select { coded.key?(it.id) && coded[it.id][:last_hour] < @now - 3.days })
      ]
    end
  end

  # Unshipped hours held by the people who should ship.
  def ship_now_seconds
    ids = nudges.first.ids.to_set
    @people.select { ids.include?(it.id) }.sum { it.hours.unshipped_seconds }
  end

  # d. The queues as reviewers see them, and how long each verdict takes.
  def review
    @review ||= begin
      reviewed = ships.select(&:reviewed_at)
      sent_back = reviewed.select { it.review_status == "changes_needed" }
      by_pet = ships.group_by(&:project_id)
      Review.new(
        review_queue: queue(Ship.awaiting_review, :created_at), fraud_queue: queue(Ship.awaiting_fraud, :reviewed_at),
        to_review: median(reviewed.map { it.reviewed_at - it.created_at }),
        to_fraud: median(ships.select { it.fraud_reviewed_at && it.reviewed_at }.map { it.fraud_reviewed_at - it.reviewed_at }),
        reviewed: reviewed.size, sent_back: sent_back.size,
        shipped_again: sent_back.count { |s| by_pet[s.project_id].any? { it.created_at > s.created_at } },
        claimed: finished_ships.sum(&:claimed_seconds), approved: finished_ships.sum { it.approved_seconds.to_i }
      )
    end
  end

  # e. People with any hours by their total, split at 30 minutes, an hour,
  # and each goal.
  def histogram
    @histogram ||= begin
      edges = [ 0, 30.minutes.to_i, 1.hour.to_i, *Goal.all.map(&:seconds) ].uniq.sort
      with_time = @people.select { it.hours.total_seconds.positive? }
      edges.each_with_index.map do |from, i|
        to = edges[i + 1]
        within = with_time.select { |p| p.hours.total_seconds >= from && (to.nil? || p.hours.total_seconds < to) }
        label = if from.zero? then "under #{span(to)}" elsif to.nil? then "#{span(from)} and more" else "#{span(from)} to #{span(to)}" end
        Bucket.new(from:, to:, label:, goal: Goal.all.find { it.seconds == from }, group: collect("hours_#{i}", "#{label} in total", within))
      end
    end
  end

  def goals
    @goals ||= Goal.all.map do |g|
      GoalRow.new(
        goal: g,
        total: collect("goal_#{g.key}_total", "#{g.hours}h in total, the #{g.key} goal", @people.select { it.hours.total_seconds >= g.seconds }),
        approved: collect("goal_#{g.key}_approved", "#{g.hours}h approved, the #{g.key} goal", @people.select { it.hours.approved_seconds >= g.seconds }),
        redeemed: collect("goal_#{g.key}_redeemed", "redeemed the #{g.key} goal", @people.select { |p| p.redemptions.any? { it.goal_key == g.key } }),
        fulfilled: collect("goal_#{g.key}_fulfilled", "got the #{g.key} goal fulfilled",
                         @people.select { |p| p.redemptions.any? { it.goal_key == g.key && it.status == "fulfilled" } })
      )
    end
  end

  # f. Pets with unshipped hours that never shipped, and the offline ship
  # checks they fail. Banned people's pets are left out.
  def pets
    @pets ||= begin
      waiting = @people.reject { it.user.banned? }.flat_map do |p|
        p.projects.select { |pet| p.ships.none? { it.project_id == pet.id } && pet.unshipped_seconds([]).positive? }
      end
      unmet = waiting.index_with { SubmitGate.new(it).unmet_offline }
      conditions = SubmitGate::OFFLINE.keys.map do |key|
        failing = waiting.select { unmet[it].include?(key) }
        PetCondition.new(key:, label: PET_CONDITIONS.fetch(key), pets: failing.size,
                         owners: collect("pets_#{key}", "own a pet with unshipped hours, never shipped, missing #{PET_CONDITIONS.fetch(key)}",
                                       failing.map(&:user_id).uniq))
      end
      ready = waiting.select { unmet[it].empty? }
      Pets.new(count: waiting.size, seconds: waiting.sum { it.unshipped_seconds([]) }, conditions: conditions.sort_by { -it.pets },
               ready_pets: ready.size,
               ready: collect("pets_ready", "own a pet with unshipped hours that meets every offline check and never shipped", ready.map(&:user_id).uniq))
    end
  end

  # g. What reviewers asked participants to change, newest first.
  def feedback
    Ship.where(review_status: "changes_needed", user: User.where(admin: false)).where.not(review_feedback: [ nil, "" ])
        .includes(:project).order(reviewed_at: :desc).limit(10)
  end

  # h. Signups on each day of the program window, in its time zone. Days
  # still to come have none.
  def signups
    @signups ||= begin
      window = ProgramWindow.current
      zone = ActiveSupport::TimeZone[ProgramWindow::ZONE]
      first = window.starts_at.in_time_zone(zone).to_date
      last = (window.ends_at - 1).in_time_zone(zone).to_date
      by_day = @people.select { it.user.created_at >= window.starts_at }.group_by { it.user.created_at.in_time_zone(zone).to_date }
      Signups.new(
        days: (first..last).map { |date| Day.new(date:, group: collect("signed_up_#{date.iso8601}", "signed up on #{date.strftime("%B %-d")}", by_day.fetch(date, []))) },
        before: collect("signed_up_before", "signed up before the program window opened", @people.select { it.user.created_at < window.starts_at })
      )
    end
  end

  # i. Coding time on each Eastern day of the window, with that day's signups.
  def coding_days
    @coding_days ||= begin
      signed = signups.days.to_h { [ it.date, it.group ] }
      @coding.per_day.map { |day| CodingDay.new(**day, signups: signed[day[:date]], counted: day[:date] <= today) }
    end
  end

  # The window's days up to today, each with who was active on it. Active
  # is stricter than the coding days' people, who count with any time. Each
  # day also counts the side guides' people, who have no account here.
  def active_days
    @active_days ||= begin
      coded = @coding.per_day_and_user(at_least: ACTIVE_CODING_SECONDS)
      users = @people.to_h { [ it.id, it.user ] }
      days = coding_days.select(&:counted)
      readers = GuideReaderDay.per_day(days.map(&:date))
      stardance = StardanceActiveDay.per_day(days.map(&:date))
      days.map do |day|
        people = coded.fetch(day.date, []).filter_map { |id, seconds| Active.new(user: users[id], reasons: { coded: seconds }) if users[id] }
        counted = stardance[day.date]
        read = readers.fetch(day.date, {})
        read = read.merge("stardance" => counted.active) if counted
        ActiveDay.new(date: day.date, people: people.sort_by { [ -it.seconds, it.user.id ] }, today: day.date == today,
                      readers: read, stardance: counted)
      end
    end
  end

  # The day grid: a column per week, Sunday first, each 7 days, nil for a
  # day outside the window.
  def coding_weeks
    days = coding_days.index_by(&:date)
    return [] if days.empty?
    (days.keys.min.beginning_of_week(:sunday)..days.keys.max.end_of_week(:sunday)).each_slice(7).map { |week| week.map { days[it] } }
  end

  # The average seconds coded in each Eastern hour of each weekday so far:
  # averages[wday][hour], wday 0 for Sunday. The window's sum for a weekday
  # is divided by how many times that weekday has come, so a weekday that
  # came twice doesn't look twice as busy. nil for a weekday yet to come.
  def hour_grid
    @hour_grid ||= begin
      zone = ProgramWindow::ZONE
      first = ProgramWindow.current.starts_at.in_time_zone(zone).to_date
      last = [ (ProgramWindow.current.ends_at - 1).in_time_zone(zone).to_date, today ].min
      times = (first..last).map(&:wday).tally
      @coding.hour_of_day_grid.each_with_index.map { |hours, wday| times[wday] && hours.map { it.fdiv(times[wday]) } }
    end
  end

  # The busiest hours of the week, [seconds, wday, hour], busiest first.
  def busiest_hours(count = 3)
    hour_grid.each_with_index.flat_map { |averages, wday| averages.to_a.each_with_index.map { |seconds, hour| [ seconds, wday, hour ] } }
             .select { it[0].positive? }.max_by(count, &:first)
  end

  # When Hackatime was last asked for each linked participant's coding hours.
  def fetches
    linked = @people.select { it.user.hackatime_linked }
    ages = linked.filter_map { @now - it.user.coding_hours_synced_at if it.user.coding_hours_synced_at }
    Fetches.new(linked: linked.size, oldest: ages.max, median: median(ages), never: linked.size - ages.size)
  end

  # j. Whether coding is speeding up or slowing down.
  def momentum
    @momentum ||= begin
      window = ProgramWindow.current
      weeks = @coding.last_two_weeks(@now)
      # A window younger than a week has had less than a week to code in.
      span = (@now - window.starts_at).clamp(0, 7.days.to_f)
      so_far = coding_days.sum(&:seconds)
      left = window.ends_at - @now
      projected = so_far + weeks[:last_7_days] / span * left if span.positive? && left.positive?
      Momentum.new(**weeks, span:, coded: so_far, projected:, to_first_code: median(first_code_waits))
    end
  end

  # People by when they last coded.
  def coders
    @coders ||= {
      today: collect("coded_today", "coded today, US Eastern time", @people.select { coded.key?(it.id) && coded[it.id][:last_hour] >= today_began }),
      week: collect("coded_7_days", "coded in the last 7 days", @people.select { coded.key?(it.id) && coded[it.id][:last_hour] >= @now - 7.days }),
      ever: collect("coded_ever", "coded at least once in the window", @people.select { coded.key?(it.id) })
    }
  end

  private

  def ships = @ships ||= @people.flat_map(&:ships)
  def coded = @coded ||= @coding.first_and_last_hours
  def today = @now.in_time_zone(ProgramWindow::ZONE).to_date
  def today_began = @now.in_time_zone(ProgramWindow::ZONE).beginning_of_day

  # From signing up, or the window opening if later, to the first hour with
  # time. Time before signing up counts as none to wait.
  def first_code_waits
    opened = ProgramWindow.current.starts_at
    @people.filter_map { |p| [ coded[p.id][:first_hour] - [ p.user.created_at, opened ].max, 0 ].max if coded.key?(p.id) }
  end
  def finished_ships = @finished_ships ||= ships.select { it.approved? || it.rejected? }

  # Takes people or user ids.
  def collect(key, label, members)
    @groups[key] = Group.new(key:, label:, ids: members.map { it.is_a?(Person) ? it.id : it })
  end

  # The lowest goal they have not redeemed and their approved hours have
  # not reached: shipping is what would get them there.
  def should_ship?(person)
    return false if person.ships.any?(&:pending?)
    redeemed = person.redemptions.map(&:goal_key)
    goal = Goal.all.find { !redeemed.include?(it.key) && person.hours.approved_seconds < it.seconds }
    goal.present? && person.hours.total_seconds >= goal.seconds
  end

  def redeemable(person)
    redeemed = person.redemptions.map(&:goal_key)
    Goal.all.select { person.hours.approved_seconds >= it.seconds && !redeemed.include?(it.key) }
  end

  # Pets whose latest ship was sent back for changes.
  def sent_back_pets(person)
    person.ships.group_by(&:project_id).values.select { it.max_by(&:created_at).changes_needed? }
  end

  def queue(scope, since)
    ships = Ship.arel_table
    count, oldest, seconds = scope.unscope(:order).pick(Arel.star.count, ships[since].minimum, ships[:claimed_seconds].sum)
    Waiting.new(count:, oldest:, seconds: seconds.to_i)
  end

  def median(values)
    return if values.empty?
    sorted = values.sort
    (sorted[(sorted.size - 1) / 2] + sorted[sorted.size / 2]) / 2.0
  end

  def fraction(part, whole) = whole.zero? ? nil : part.to_f / whole

  # "30m", "1h", "2h 30m".
  def span(seconds) = seconds < 1.hour ? "#{seconds / 60}m" : Hours.format(seconds).delete_suffix(" 0m")
end
