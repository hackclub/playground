require "test_helper"

# The stats page on a small known set of participants, one or a few at each
# step, with every number worked out by hand. Times are UTC. The window opens
# at 9am Eastern on September 28, and it is noon Eastern on September 30.
class AdminStatsTest < ActionDispatch::IntegrationTest
  H = 3600
  NOW = Time.utc(2026, 9, 30, 16)
  SHOT = [ { "id" => "s1", "key" => "shots/a.png", "url" => "https://playground.hackclub-assets.com/shots/a.png" } ].freeze

  setup do
    travel_to NOW
    ProgramWindow.current = ProgramWindow.new(starts_at: Time.utc(2026, 9, 28, 13), ends_at: Time.utc(2026, 10, 10, 13))
    @admin = log_in("admin")
    pet(@admin, "modpet", tracked: 8 * H)
    built = Time.utc(2026, 9, 29, 2)

    ann = person("ann", created: Time.utc(2026, 9, 28, 14), verified: false, hackatime: false)
    pet(ann, "annpet", tracked: 20 * 60)
    person("ben", created: Time.utc(2026, 9, 28, 15), hackatime: false)
    person("cat", created: Time.utc(2026, 9, 30, 10), hackatime: false)
    # On the window's first day, before it opened.
    person("pia", created: Time.utc(2026, 9, 28, 12), hackatime: false)
    person("ned", created: Time.utc(2026, 9, 20))
    pet(person("dan", created: built), "danpet", tracked: 0, projects: [], refreshed: nil)
    eve = person("eve", created: built)
    pet(eve, "evepet", tracked: H, description: "hops", shots: [], refreshed: 3.days)
    pet(eve, "evetwo", tracked: 30 * 60, description: nil, code: nil, playable: nil)
    pet(person("fay", created: built), "faypet", tracked: 3 * H, refreshed: 1.day)

    ship(pet(person("gus", created: built), "guspet", tracked: 3 * H), 3 * H, at: Time.utc(2026, 9, 30, 10))
    hal = person("hal", created: built)
    ship(pet(hal, "halpet", tracked: 6 * H), 4 * H, at: Time.utc(2026, 9, 29, 4), verdict: :approved, reviewed: Time.utc(2026, 9, 29, 8),
                                                   review_seconds: 3 * H, fraud: Time.utc(2026, 9, 29, 10), deduction: 30 * 60)
    redeem(hal, "stickers", "pending")
    ivy = person("ivy", created: built)
    ship(pet(ivy, "ivypet", tracked: 12 * H), 12 * H, at: Time.utc(2026, 9, 29, 5), verdict: :approved, reviewed: Time.utc(2026, 9, 29, 13),
                                                     fraud: Time.utc(2026, 9, 29, 14))
    redeem(ivy, "stickers", "fulfilled")
    ship(pet(person("jay", created: built), "jaypet", tracked: 2 * H, refreshed: nil), 2 * H, at: Time.utc(2026, 9, 29, 6),
         verdict: :changes_needed, reviewed: Time.utc(2026, 9, 29, 8), feedback: "add a screenshot")
    kim = pet(person("kim", created: built), "kimpet", tracked: 3 * H)
    ship(kim, 2 * H, at: Time.utc(2026, 9, 29, 7), verdict: :changes_needed, reviewed: Time.utc(2026, 9, 29, 9), feedback: "the README is empty")
    ship(kim, 3 * H, at: Time.utc(2026, 9, 30, 12))
    ship(pet(person("leo", created: built, banned: true), "leopet", tracked: 5 * H), 5 * H, at: Time.utc(2026, 9, 29, 8),
         verdict: :rejected, reviewed: Time.utc(2026, 9, 29, 11))
    ship(pet(person("ola", created: built), "olapet", tracked: 2 * H), 2 * H, at: Time.utc(2026, 9, 30, 6),
         verdict: :fraud_pending, reviewed: Time.utc(2026, 9, 30, 8))

    # Coding hours, each the UTC start of an hour. Eastern time is UTC-4, so
    # 04:00 UTC is Eastern midnight.
    code("ivy", Time.utc(2026, 9, 28, 13), 900)   # Mon 9am, the window's first hour
    code("gus", Time.utc(2026, 9, 28, 14), 1800)  # Mon 10am
    code("hal", Time.utc(2026, 9, 29, 3), H)      # Mon 11pm
    code("hal", Time.utc(2026, 9, 29, 4), 600)    # Tue midnight
    code("leo", Time.utc(2026, 9, 29, 20), 3000)  # Tue 4pm, banned
    code("fay", Time.utc(2026, 9, 30, 3), 2400)   # Tue 11pm, not today
    code("ann", Time.utc(2026, 9, 30, 4), 300)    # Wed midnight, today
    code("gus", Time.utc(2026, 9, 30, 15), 1200)  # Wed 11am, today
    CodingHour.create!(user: @admin, hour: Time.utc(2026, 9, 29, 20), seconds: H)
    User.find_by!(display_name: "gus").update_columns(coding_hours_synced_at: NOW - 30.minutes)
    User.find_by!(display_name: "hal").update_columns(coding_hours_synced_at: NOW - 2.hours)
    @stats = ProgramStats.new
  end

  test "a: hours by stage, hours cut, and how old the refreshes are" do
    assert_equal({ approved: 52200, pending: 28800, unshipped: 31800 }, @stats.hours_by_stage)
    cut = @stats.cut
    assert_equal [ H, 30 * 60, 5 * H, 23400 ], [ cut.deflated, cut.deducted, cut.rejected, cut.total ]
    refreshes = @stats.refreshes
    assert_equal [ 11, 3.days.to_i, H, 1 ], [ refreshes.pets, refreshes.oldest.to_i, refreshes.median.to_i, refreshes.never ]

    get admin_stats_path
    assert_response :success
    assert_select "svg.pie pattern#pie-pending image[href*='meter/pending']"
    assert_select "svg.pie path.approved", 1
    assert_select ".kv.stages tr", text: /approved\s*14h 30m\s*46%/
    assert_select ".kv.stages tr", text: /pending\s*8h 0m\s*26%/
    assert_select ".kv.stages tr", text: /unshipped\s*8h 50m\s*28%/
    assert_select ".kv.stages tr.total", text: /31h 20m/
    assert_match "cut in review: 6h 30m", text_of_page
    assert_match "the oldest refresh is 3d 0h old, the median 1h 0m. 1 pet with Hackatime projects never refreshed.", text_of_page
  end

  test "a: people active each day, with a minute or more in Hackatime, a bar a day up to today, today pressed" do
    # eve's 50 seconds today are under a minute, so she is not active. dan's
    # two half minutes on Tuesday add up to one, so he is. The coding days
    # still count anyone with time.
    code("eve", Time.utc(2026, 9, 30, 14), 50)
    code("dan", Time.utc(2026, 9, 29, 14), 30)
    code("dan", Time.utc(2026, 9, 29, 15), 30)
    stats = ProgramStats.new
    days = stats.active_days
    assert_equal [ Date.new(2026, 9, 28), Date.new(2026, 9, 29), Date.new(2026, 9, 30) ], days.map(&:date)
    assert_equal [ 3, 4, 2 ], days.map(&:count)
    assert_equal [ 3, 4, 3 ], stats.coding_days.first(3).map(&:people)
    assert_equal [ false, false, true ], days.map(&:today)
    # hal's 11pm Monday hour is Monday's, and his midnight is Tuesday's. leo
    # is banned and still counts, as the coding days count him.
    assert_equal [ [ "hal", { coded: 3600 } ], [ "gus", { coded: 1800 } ], [ "ivy", { coded: 900 } ] ],
                 days[0].people.map { [ it.user.display_name, it.reasons ] }
    assert_equal [ %w[leo fay hal dan], [ 3000, 2400, 600, 60 ] ], days[1].people.map { [ it.user.display_name, it.seconds ] }.transpose
    assert_equal [ %w[gus ann], [ 1200, 300 ] ], days[2].people.map { [ it.user.display_name, it.seconds ] }.transpose

    get admin_stats_path
    assert_select "section h2", text: "how many people are active each day?"
    sections = css_select("section.panel h2").map(&:text)
    assert_equal sections.index("how many hours, in which stage?") + 1, sections.index("how many people are active each day?")
    assert_match "active: at least 1 minute in Hackatime that day.", text_of_page
    assert_select ".dau button.dau-day", 3
    assert_equal [ %w[2026-09-28 false -1], %w[2026-09-29 false -1], %w[2026-09-30 true 0] ],
                 css_select(".dau button.dau-day").map { |day| %w[data-date aria-pressed tabindex].map { day[it] } }
    assert_select "button.dau-day[aria-label=?][aria-controls='active-2026-09-28']", "Mon September 28: 3 people active", text: /3\s*28/
    assert_select "button.dau-day[aria-label=?]", "Tue September 29: 4 people active", text: /4\s*29/
    assert_select "button.dau-day[aria-label=?]", "Wed September 30: 2 people active", text: /2\s*30/
    assert_select "button.dau-day .fill", 3
    assert_match "September 28 to September 30, in US Eastern time.", text_of_page

    assert_select ".dau-list", 3
    assert_select ".dau-list[hidden]", 2
    assert_select ".dau-list#active-2026-09-30:not([hidden])" do |list|
      assert_select "h3", text: "today, Wednesday September 30: 2 people active"
      assert_equal [ [ "gus", "coded 20m" ], [ "ann", "coded 5m" ] ], list.css("tr").map { |row| row.css("td").map { it.text.strip } }.reject(&:empty?)
      assert_select "a[href=?]", admin_person_path(User.find_by!(display_name: "gus")), text: "gus"
      assert_select "a[href=?]", admin_person_path(User.find_by!(display_name: "ann")), text: "ann"
      assert_select "a", text: "eve", count: 0
    end
    assert_select ".dau-list#active-2026-09-29[hidden]" do |list|
      assert_select "h3", text: "Tuesday September 29: 4 people active"
      assert_equal %w[leo fay hal dan], list.css("td a").map(&:text)
      assert_equal [ "coded 50m", "coded 40m", "coded 10m", "coded 1m" ], list.css("td:last-child").map(&:text)
    end
    assert_select ".dau-list a[href=?]", admin_person_path(@admin), 0
  end

  test "a: a day nobody was active has an empty bar and says so, and it is pressed when it is today" do
    travel_to Time.utc(2026, 10, 2, 16)
    get admin_stats_path
    assert_equal [ %w[2026-09-28 false], %w[2026-09-29 false], %w[2026-09-30 false], %w[2026-10-01 false], %w[2026-10-02 true] ],
                 css_select(".dau button.dau-day").map { |day| %w[data-date aria-pressed].map { day[it] } }
    assert_select "button.dau-day[data-date='2026-10-01'][aria-label=?]", "Thu October 1: 0 people active"
    assert_select "button.dau-day[data-date='2026-10-01'] .fill", 0
    assert_select "button.dau-day[data-date='2026-10-01'] .count", 0
    assert_select ".dau-list#active-2026-10-02:not([hidden])" do
      assert_select "h3", text: "today, Friday October 2: 0 people active"
      assert_select "p.muted", text: "nobody was active on this day."
      assert_select "table", 0
    end
    assert_select ".dau-list#active-2026-10-01[hidden] p.muted", text: "nobody was active on this day."
  end

  test "a: a day with time only under a minute charts nobody active" do
    travel_to Time.utc(2026, 10, 2, 16)
    code("eve", Time.utc(2026, 10, 2, 14), 40)
    code("fay", Time.utc(2026, 10, 2, 15), 59)
    stats = ProgramStats.new
    assert_equal [ 0, 2 ], [ stats.active_days.last.count, stats.coding_days.find { it.date == Date.new(2026, 10, 2) }.people ]
    get admin_stats_path
    assert_select "button.dau-day[data-date='2026-10-02'][aria-pressed=true][aria-label=?]", "Fri October 2: 0 people active"
    assert_select "button.dau-day[data-date='2026-10-02'] .fill", 0
    assert_select ".dau-list#active-2026-10-02:not([hidden]) p.muted", text: "nobody was active on this day."
  end

  test "a: after the window closes its last day is pressed" do
    travel_to Time.utc(2026, 10, 12, 16)
    get admin_stats_path
    assert_select ".dau button.dau-day", 13
    assert_select ".dau button.dau-day[aria-pressed=true]", 1
    assert_select ".dau button.dau-day[aria-pressed=true][data-date='2026-10-10']"
    assert_select ".dau-list:not([hidden])", 1
    assert_select ".dau-list#active-2026-10-10:not([hidden]) h3", text: "Saturday October 10: 0 people active"
  end

  test "a: before the window opens there are no days to chart" do
    travel_to Time.utc(2026, 9, 28, 3) # 11pm Eastern the day before
    get admin_stats_path
    assert_select ".dau", 0
    assert_match "how many people are active each day? the program window hasn't opened yet.", text_of_page
  end

  test "b: the funnel counts each step over everyone who passed the steps above" do
    steps = @stats.funnel.index_by(&:key)
    assert_equal [ 15, 14, 11, 10, 9, 9, 7, 6, 2, 2, 1 ], @stats.funnel.map { it.reached.count }
    assert_equal %w[ann], names(steps[:eligible].stuck)
    assert_equal %w[ben cat pia], names(steps[:hackatime].stuck)
    assert_equal %w[ned], names(steps[:pet].stuck)
    assert_equal %w[dan], names(steps[:linked].stuck)
    assert_equal [], names(steps[:tracked].stuck)
    assert_equal %w[eve leo], names(steps[:first_goal].stuck)
    assert_equal %w[fay], names(steps[:shipped].stuck)
    assert_equal %w[gus jay kim ola], names(steps[:approved].stuck)
    assert_equal %w[hal], names(steps[:fulfilled].stuck)
    assert_equal [ :approved ], @stats.funnel.select(&:biggest_drop).map(&:key)
    assert_in_delta 2 / 6.0, steps[:approved].share

    get admin_stats_path
    assert_select ".funnel tr", text: /a ship approved\s*2\s*33%\s*4\s*biggest drop/
    assert_select ".funnel a[href=?]", admin_people_path(filter: "stuck_approved"), text: "4"
    assert_select ".funnel a[href=?]", admin_people_path(filter: "reached_signed_up"), text: "15"
    assert_select ".late", count: 1
  end

  test "c: who to nudge" do
    nudges = @stats.nudges.index_by(&:key)
    assert_equal %w[fay jay], names(nudges["ship_now"])
    assert_equal 5 * H, @stats.ship_now_seconds
    assert_equal %w[ann ben pia], names(nudges["no_hackatime"])
    assert_equal %w[ivy], names(nudges["redeem_now"])
    assert_equal %w[jay], names(nudges["changes_back"])
    assert_equal [], names(nudges["went_quiet"])

    get admin_stats_path
    assert_select "a.card[href=?]", admin_people_path(filter: "ship_now"), text: /\A\s*2\s*enough hours for their next goal.*holding 5h 0m unshipped/m
  end

  test "d: the review queues and how long verdicts take" do
    review = @stats.review
    assert_equal [ 2, Time.utc(2026, 9, 30, 10), 6 * H ], review.review_queue.to_h.values
    assert_equal [ 1, Time.utc(2026, 9, 30, 8), 2 * H ], review.fraud_queue.to_h.values
    assert_equal [ 2.5 * H, 1.5 * H ], [ review.to_review, review.to_fraud ]
    assert_equal [ 6, 2, 1 ], [ review.reviewed, review.sent_back, review.shipped_again ]
    assert_equal [ 21 * H, 52200 ], [ review.claimed, review.approved ]

    get admin_stats_path
    page = text_of_page
    assert_match "waiting for review 2 ships · oldest waiting 6h 0m · 6h 0m pending", page
    assert_match "waiting for fraud 1 ship · oldest waiting 8h 0m · 2h 0m pending", page
    assert_match "ship to review verdict median 2h 30m", page
    assert_match "review to fraud verdict median 1h 30m", page
    assert_match "sent back for changes 33% of 6 reviewed ships", page
    assert_match "shipped again after changes 50%, 1 of 2", page
    assert_match "approved of claimed hours 69%, 14h 30m of 21h 0m on finished ships", page
  end

  test "e: people by total hours, and each goal reached, redeemed, and fulfilled" do
    buckets = @stats.histogram
    assert_equal [ "under 30m", "30m to 1h", "1h to 2h", "2h to 5h", "5h to 10h", "10h and more" ], buckets.map(&:label)
    assert_equal [ 1, 0, 1, 6, 0, 1 ], buckets.map { it.group.count }
    assert_equal [ nil, nil, nil, "stickers", "keychain", "shirt" ], buckets.map { it.goal&.key }
    assert_equal %w[fay gus hal jay kim ola], names(buckets[3].group)
    goals = @stats.goals.to_h { [ it.goal.key, [ it.total, it.approved, it.redeemed, it.fulfilled ].map(&:count) ] }
    assert_equal({ "stickers" => [ 7, 2, 2, 1 ], "keychain" => [ 1, 1, 0, 0 ], "shirt" => [ 1, 1, 0, 0 ] }, goals)

    get admin_stats_path
    assert_select ".bars td.mark", 9
    assert_select ".bars .marks td.mark", text: /2h\s+stickers/
    assert_select ".bars a[href=?]", admin_people_path(filter: "hours_3"), text: "6"
    assert_select "a[href=?]", admin_people_path(filter: "goal_stickers_fulfilled"), text: "1"
  end

  test "f: what the unshipped pets are missing, without the network" do
    pets = @stats.pets
    assert_equal [ 4, 17400, 1 ], [ pets.count, pets.seconds, pets.ready_pets ]
    assert_equal %w[fay], names(pets.ready)
    missing = pets.conditions.to_h { [ it.key, [ it.pets, names(it.owners) ] ] }
    assert_equal({ eligible: [ 1, %w[ann] ], description: [ 1, %w[eve] ], description_length: [ 1, %w[eve] ], hackatime_projects: [ 0, [] ],
                   repo: [ 1, %w[eve] ], playable: [ 1, %w[eve] ], screenshot: [ 1, %w[eve] ] }, missing)

    get admin_stats_path
    assert_match "4 pets hold 4h 50m unshipped and never shipped.", text_of_page
    assert_select "tr", text: /a code link\s*1\s*1/
    assert_select "a[href=?]", admin_people_path(filter: "pets_ready"), text: "1"
  end

  test "f: the offline checks never reach GitHub or load a link" do
    gate = SubmitGate.new(Project.find_by!(name: "evetwo"))
    %i[repo release status_ok?].each { |m| gate.define_singleton_method(m) { |*| flunk "the offline checks called #{m}" } }
    assert_equal %i[description repo playable], gate.unmet_offline

    originals = %i[repo release_for].index_with { Github.method(it) }
    originals.each_key { |m| Github.define_singleton_method(m) { |*| flunk "the stats called Github.#{m}" } }
    assert_equal 4, ProgramStats.new.pets.count
  ensure
    originals&.each { |m, original| Github.define_singleton_method(m, original) }
  end

  test "g: the latest feedback asking for changes, newest first" do
    assert_equal [ "the README is empty", "add a screenshot" ], @stats.feedback.map(&:review_feedback)

    get admin_stats_path
    assert_select "td a[href=?]", admin_ship_path(Ship.find_by(review_feedback: "the README is empty")), text: "kimpet"
  end

  test "h: signups per Eastern day of the whole window" do
    signups = @stats.signups
    counts = signups.days.to_h { [ it.date.iso8601, it.group.count ] }
    assert_equal 13, counts.size
    assert_equal({ "2026-09-28" => 12, "2026-09-29" => 0, "2026-09-30" => 1, "2026-10-10" => 0 }, counts.slice(*%w[2026-09-28 2026-09-29 2026-09-30 2026-10-10]))
    assert_equal %w[ned pia], names(signups.before)

    get admin_stats_path
    assert_select ".bars a[href=?]", admin_people_path(filter: "signed_up_2026-09-28"), text: "12"
    assert_match "September 28 to October 10, in US Eastern time.", text_of_page
  end

  test "i: coding time per Eastern day, split at Eastern midnight, with nothing for days to come" do
    days = @stats.coding_days
    assert_equal 13, days.size
    assert_equal [ [ Date.new(2026, 9, 28), 6300, 3, 12 ], [ Date.new(2026, 9, 29), 6000, 3, 0 ], [ Date.new(2026, 9, 30), 1500, 2, 1 ] ],
                 days.first(3).map { [ it.date, it.seconds, it.people, it.signups.count ] }
    assert_equal [ true, true, true, false ], days.first(4).map(&:counted)
    assert_equal [ Date.new(2026, 9, 28), Date.new(2026, 10, 4) ], @stats.coding_weeks.map { it.compact.first.date }

    get admin_stats_path
    assert_equal [ "Sep 28", "Oct 4" ], css_select(".heat.days th[scope=col]").map(&:text)
    assert_select ".heat.days td[class^=l]", 3
    assert_select ".heat.days td.l4[title=?]", "Mon September 28: 1h 45m, 3 people coding", text: "Mon September 28: 1h 45m, 3 people coding"
    assert_select ".heat.days td.l4[title=?]", "Tue September 29: 1h 40m, 3 people coding"
    assert_select ".heat.days td.l1[title=?]", "Wed September 30: 25m, 2 people coding"
    assert_select "details table tr", 4
    assert_match "the busiest day had 1h 45m coded", text_of_page
  end

  test "i: the hour of the day grid averages each weekday over the times it has come" do
    grid = @stats.hour_grid
    assert_equal [ nil, nil, nil, nil ], grid.values_at(0, 4, 5, 6)
    assert_equal({ 9 => 900, 10 => 1800, 23 => 3600 }, grid[1].each_with_index.to_h { [ _2, _1 ] }.select { _2.positive? })
    assert_equal({ 0 => 600, 16 => 3000, 23 => 2400 }, grid[2].each_with_index.to_h { [ _2, _1 ] }.select { _2.positive? })
    assert_equal({ 0 => 300, 11 => 1200 }, grid[3].each_with_index.to_h { [ _2, _1 ] }.select { _2.positive? })
    assert_equal [ [ H, 1, 23 ], [ 3000, 2, 16 ], [ 2400, 2, 23 ] ], @stats.busiest_hours

    get admin_stats_path
    assert_select ".heat.hours td[class^=l]", 72
    assert_select ".heat.hours td.l4[title=?]", "mon 11pm: 1h 0m on average"
    assert_match "busiest: mon 11pm (1h 0m), tue 4pm (50m), tue 11pm (40m).", text_of_page
    assert_match "the oldest fetch is 2h 0m old, the median 1h 15m. 9 participants with Hackatime linked not fetched yet.", text_of_page
  end

  test "i: a weekday that came twice is averaged over both" do
    code("gus", Time.utc(2026, 10, 6, 1), 1800) # the next Monday, 9pm
    travel_to Time.utc(2026, 10, 6, 16)
    assert_equal 900, ProgramStats.new.hour_grid[1][21]
  end

  test "j: the last two weeks, who is coding, the projection, and the wait to code" do
    momentum = @stats.momentum
    assert_equal [ 13800, 0, 13800 ], [ momentum.last_7_days, momentum.previous_7_days, momentum.coded ]
    # The window is 2d 3h old and has 9d 21h to go.
    assert_in_delta 13800 + 13800.0 / (51 * H) * (237 * H), momentum.projected
    # From signup, or the window opening, to the first coded hour: 0 for ivy
    # and gus, who coded before signing up, 1h, 18h, 25h, and 38h.
    assert_equal 9.5 * H, momentum.to_first_code
    coders = @stats.coders
    assert_equal %w[ann gus], names(coders[:today])
    assert_equal %w[ann fay gus hal ivy leo], names(coders[:week])
    assert_equal names(coders[:week]), names(coders[:ever])

    get admin_stats_path
    page = text_of_page
    assert_match "last 7 days 3h 50m coded · none in the 7 days before", page
    assert_match "people coding 2 today · 6 in the last 7 days", page
    assert_match "coded in the window 3h 50m", page
    assert_match "projection for the end about 21h 38m by 9am Eastern time on October 10, 2026, if the last 7 days' pace holds", page
    assert_match "signup to first coded hour median 9h 30m, over the 6 who have coded", page
    assert_select "a[href=?]", admin_people_path(filter: "coded_today"), text: "2"
  end

  test "j: a week on the week before" do
    code("ivy", Time.utc(2026, 10, 7, 20), H)
    code("ivy", Time.utc(2026, 10, 7, 21), H)
    travel_to Time.utc(2026, 10, 8, 16)
    momentum = ProgramStats.new.momentum
    # The last week starts on October 1 at 16:00, so only ivy's two hours
    # are in it, and every earlier hour is in the week before.
    assert_equal [ 2 * H, 13800 ], [ momentum.last_7_days, momentum.previous_7_days ]
    get admin_stats_path
    assert_match "2h 0m coded · down 48% on the 7 days before (3h 50m)", text_of_page
  end

  test "c: who went quiet, coded before but not in the last 3 days" do
    code("kim", Time.utc(2026, 10, 3, 20), 600)
    travel_to NOW + 4.days
    quiet = ProgramStats.new.nudges.index_by(&:key)["went_quiet"]
    # leo is banned, and kim coded a day ago.
    assert_equal %w[ann fay gus hal ivy], names(quiet)
    get admin_people_path(filter: "went_quiet")
    assert_equal %w[ann fay gus hal ivy], css_select("table.list td:first-child a").map(&:text).sort
  end

  test "every count links to a people page listing exactly those people" do
    get admin_stats_path
    keys = css_select("a[href*='filter=']").map { Rack::Utils.parse_query(URI(it["href"]).query)["filter"] }.uniq
    assert_operator keys.size, :>, 30
    keys.each do |key|
      group = ProgramStats.new.group_for(key)
      get admin_people_path(filter: key)
      assert_equal names(group), css_select("table.list td:first-child a").map(&:text).sort, key
      assert_select "p.filter", text: /#{Regexp.escape(group.label)}.*#{group.count} #{group.count == 1 ? "person" : "people"}/
    end
  end

  test "a filter works with the search box, and clearing it keeps the search" do
    get admin_people_path(filter: "stuck_approved")
    assert_equal %w[gus jay kim ola], css_select("table.list td:first-child a").map(&:text).sort
    assert_select "a[href=?]", admin_people_path, text: "clear filter"

    get admin_people_path(filter: "stuck_approved", q: "kim")
    assert_equal %w[kim], css_select("table.list td:first-child a").map(&:text)
    assert_select "form input[type=hidden][name=filter][value=stuck_approved]"
    assert_select "a[href=?]", admin_people_path(q: "kim"), text: "clear filter"

    get admin_people_path(filter: "no-such-group")
    assert_select "p.filter", text: /unknown/
    assert_select "table.list td", 0
  end

  test "the stats page is for admins only" do
    delete logout_path
    get admin_stats_path
    assert_response :not_found
    log_in("participant")
    get admin_stats_path
    assert_response :not_found
  end

  test "the stats page and a filter take the same few queries however many people there are" do
    # The first page saves the admin's new display name.
    get admin_stats_path
    page, filter = queries { get admin_stats_path }, queries { get admin_people_path(filter: "went_quiet") }
    3.times do |i|
      more = person("more#{i}", created: NOW - 1.hour)
      ship(pet(more, "more#{i}pet", tracked: 3 * H), H, at: NOW - 2.hours, verdict: :changes_needed, reviewed: NOW - 1.hour, feedback: "more")
      redeem(more, "stickers", "pending")
      code("more#{i}", NOW - 3.hours, 600)
    end
    assert_equal [ page, filter ], [ queries { get admin_stats_path }, queries { get admin_people_path(filter: "went_quiet") } ]
  end

  test "with no participants each section says so in a line" do
    User.where.not(id: @admin.id).find_each { it.update_columns(admin: true) }
    get admin_stats_path
    assert_response :success
    assert_select "svg.pie", 0
    assert_select ".bars", 0
    assert_select ".funnel", 0
    assert_match "nobody has any hours yet.", text_of_page
    assert_match "nobody has signed up yet.", text_of_page
    assert_match "no pet with unshipped hours is waiting for its first ship.", text_of_page
    assert_select ".heat", 0
    assert_equal 2, text_of_page.scan("no coding time in the window yet.").size
    assert_select ".dau", 0
    assert_match "nobody has been active since the window opened.", text_of_page
  end

  private

  def person(name, created:, verified: true, hackatime: true, banned: false)
    User.create!(hca_id: "ident!#{name}", email: "#{name}@example.com", display_name: name, display_name_source: "generated",
                 verification_status: verified ? "verified" : "needs_submission", ysws_eligible: verified,
                 hackatime_access_token: ("token" if hackatime), banned_at: (NOW if banned), created_at: created)
  end

  def pet(user, name, tracked:, projects: [ name ], description: "a pet that naps on the taskbar", code: "https://github.com/p/#{name}",
          playable: "https://github.com/p/#{name}/releases", shots: SHOT, refreshed: 1.hour)
    user.projects.create!(name:, hackatime_projects: projects, tracked_seconds: tracked, tracked_at: refreshed && NOW - refreshed,
                          description:, code_url: code, playable_url: playable, screenshots: shots)
  end

  # A ship in the given state, its verdicts set straight on the row.
  def ship(pet, claimed, at:, verdict: nil, reviewed: nil, review_seconds: claimed, fraud: nil, deduction: 0, feedback: nil)
    s = pet.ships.create!(user: pet.user, claimed_seconds: claimed, created_at: at)
    review = { reviewed_at: reviewed, reviewer_id: @admin.id, review_feedback: feedback }
    case verdict
    when :approved
      s.update_columns(**review, state: "approved", review_status: "approved", review_seconds:, fraud_status: deduction.positive? ? "deducted" : "passed",
                                 fraud_reviewed_at: fraud, fraud_deduction_seconds: deduction, approved_seconds: review_seconds - deduction)
    when :fraud_pending then s.update_columns(**review, review_status: "approved", review_seconds:, fraud_status: "pending")
    when :changes_needed then s.update_columns(**review, state: "changes_needed", review_status: "changes_needed")
    when :rejected then s.update_columns(**review, state: "rejected", review_status: "rejected")
    end
    s
  end

  def code(name, hour, seconds) = CodingHour.create!(user: User.find_by!(display_name: name), hour:, seconds:)

  def redeem(user, key, status) = user.redemptions.create!(goal_key: key, address: { "line_1" => "15 Falls Road" }, status:)

  def names(group) = User.where(id: group.ids).pluck(:display_name).sort

  # The page's words, one space between each piece of text.
  def text_of_page = Nokogiri::HTML(response.body).at("body").xpath(".//text()").map(&:text).join(" ").squish

  # Queries a block makes, the query cache off so a repeat still counts.
  def queries
    count = 0
    counter = ->(*, payload) { count += 1 unless payload[:name].in?(%w[SCHEMA TRANSACTION]) }
    ActiveRecord::Base.uncached { ActiveSupport::Notifications.subscribed(counter, "sql.active_record") { yield } }
    count
  end
end
