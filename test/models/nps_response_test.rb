require "test_helper"

# The NPS form's answers, when the site asks for one, and the NPS the admin
# sees. Times are UTC. Eastern time is UTC-4 in October, so 04:00 UTC is
# Eastern midnight. It is 8am Eastern on Wednesday October 7.
class NpsResponseTest < ActiveSupport::TestCase
  NOW = Time.utc(2026, 10, 7, 12)

  setup do
    travel_to NOW
    NpsResponse.asking = true
    @ann = person("ann")
  end

  test "a score from 0 to 10 and the two required answers make an answer, and anything else is optional" do
    assert answer(@ann, 0).valid?
    assert answer(@ann, 10, anything_else: nil).valid?
    [ nil, -1, 11, 7.5 ].each { |score| assert_not answer(@ann, score).valid?, "score #{score.inspect}" }
    assert_not answer(@ann, 9, doing_well: " ").valid?
    assert_not answer(@ann, 9, improve: nil).valid?
    assert_not answer(@ann, 9, source: "email").valid?
    assert_not answer(@ann, 9, source: "ship").valid?, "an answer at ship names the pet"
    assert answer(@ann, 9, source: "ship", project: @ann.projects.create!(name: "rock")).valid?
  end

  test "which text answers are required comes from one table" do
    required = NpsResponse::QUESTIONS.select { |_, question| question[:required] }.keys
    assert_equal %i[doing_well improve], required
    blank = answer(@ann, 5, doing_well: nil, improve: nil, anything_else: nil)
    blank.validate
    assert_equal required, blank.errors.attribute_names
  end

  test "the database refuses a score outside 0 to 10 too" do
    assert_raises(ActiveRecord::StatementInvalid) { answer(@ann, 11).save!(validate: false) }
  end

  test "a participant is due with no answer in the last 12 hours, to the minute" do
    assert NpsResponse.due?(@ann), "no answer at all"
    answer(@ann, 8, created_at: NOW - 12.hours - 1.minute).save!
    assert NpsResponse.due?(@ann)
    assert_not NpsResponse.answered_within?(@ann)
    answer(@ann, 8, created_at: NOW - 11.hours - 59.minutes).save!
    assert_not NpsResponse.due?(@ann)
    assert NpsResponse.answered_within?(@ann)
    assert NpsResponse.due?(@ann, now: NOW + 2.minutes), "12 hours 1 minute after the newest answer"
    assert NpsResponse.due?(person("ben")), "another person's answer is not theirs"
    assert_equal 12.hours, NpsResponse::INTERVAL
  end

  test "nps.exe asks by itself only after a minute of Hackatime time, and a ship asks either way" do
    assert NpsResponse.due?(@ann)
    assert_not NpsResponse.ask?(@ann), "a newcomer with no time"
    CodingHour.create!(user: @ann, hour: NOW.beginning_of_hour - 3.days, seconds: 40)
    CodingHour.create!(user: person("ben"), hour: NOW.beginning_of_hour, seconds: 3600)
    assert_not NpsResponse.ask?(@ann), "40 seconds"
    CodingHour.create!(user: @ann, hour: NOW.beginning_of_hour - 1.hour, seconds: 19)
    assert_not NpsResponse.ask?(@ann), "59 seconds"
    CodingHour.where(user: @ann).last.update!(seconds: 20)
    assert NpsResponse.ask?(@ann), "60 seconds over two days"
    assert_equal 60, ProgramStats::ACTIVE_CODING_SECONDS

    answer(@ann, 8, created_at: NOW - 1.hour).save!
    assert_not NpsResponse.ask?(@ann), "answered in the last 12 hours"
    assert_not NpsResponse.due?(@ann)
    assert NpsResponse.due?(person("cat")), "a ship asks a newcomer too"
  end

  test "an admin at work, a banned person, and nobody are never asked" do
    admin = person("ada", admin: true)
    banned = person("bea")
    banned.update!(banned_at: NOW)
    [ admin, banned, nil ].each do |user|
      assert_not NpsResponse.asks?(user)
      assert_not NpsResponse.due?(user)
      assert_not NpsResponse.ask?(user)
    end
    NpsResponse.asking = false
    assert_not NpsResponse.due?(@ann)
  end

  test "an answer adds nothing to the Airtable sync" do
    @ann.update_columns(synced_at: NOW)
    before = AirtableFields.user(@ann)
    answer(@ann, 3, doing_well: "the stickers", improve: "the guide", anything_else: "hi").save!
    assert_equal before, AirtableFields.user(@ann.reload)
    assert_equal NOW, @ann.synced_at, "the user's row stays synced"
  end

  test "NPS counts 9 and 10 as promoters, 7 and 8 as passives, and 0 to 6 as detractors" do
    [ 6, 7, 8, 9 ].each_with_index { |score, i| answer(person("p#{i}"), score).save! }
    week = NpsStats.new.last_7_days
    assert_equal [ 1, 2, 1, 4 ], [ week.promoters, week.passives, week.detractors, week.people ]
    assert_equal 0, week.nps
    answer(person("ten"), 10).save!
    answer(person("zero"), 0).save!
    week = NpsStats.new.last_7_days
    assert_equal [ 2, 2, 2, 6 ], [ week.promoters, week.passives, week.detractors, week.people ]
    assert_equal 0, week.nps
  end

  test "each person counts once, by their latest answer in the 7 days" do
    answer(@ann, 10, created_at: NOW - 3.days).save!
    answer(@ann, 2, created_at: NOW - 1.day).save!
    answer(person("ben"), 9, created_at: NOW - 2.days).save!
    answer(person("cat"), 9, created_at: NOW - 1.hour).save!
    week = NpsStats.new.last_7_days
    assert_equal [ 2, 0, 1, 3 ], [ week.promoters, week.passives, week.detractors, week.people ]
    # Two promoters and a detractor of three: 67% minus 33%.
    assert_equal 33, week.nps
  end

  test "the 7 days are Eastern days, today so far included, and an older answer counts for its own days" do
    # Thursday October 1 at 1am Eastern: the 7 days to October 7 begin there.
    answer(@ann, 0, created_at: Time.utc(2026, 10, 1, 5)).save!
    # Wednesday September 30 at 11pm Eastern: too old for the week.
    answer(person("ben"), 0, created_at: Time.utc(2026, 10, 1, 3)).save!
    answer(person("cat"), 10).save!
    assert_equal [ 2, 0 ], [ NpsStats.new.last_7_days.people, NpsStats.new.last_7_days.nps ]

    days = NpsStats.new.over_time
    assert_equal (Date.new(2026, 9, 30)..Date.new(2026, 10, 7)).to_a, days.map(&:last_day)
    assert_equal [ 1, 2, 2, 2, 2, 2, 2, 2 ], days.map(&:people)
    assert_equal [ -100, -100, -100, -100, -100, -100, -100, 0 ], days.map(&:nps)
  end

  test "NPS rounds to a whole number, has none with nobody, and leaves admins out" do
    answer(@ann, 9).save!
    answer(person("ben"), 9).save!
    answer(person("cat"), 5).save!
    answer(person("ada", admin: true), 0).save!
    assert_equal 33, NpsStats.new.last_7_days.nps
    assert_nil NpsStats.new(now: NOW + 8.days).last_7_days.nps
    assert_equal 3, NpsStats.new.latest.size
  end

  private

  def person(name, admin: false)
    User.create!(hca_id: "ident!#{name}", email: "#{name}@example.com", display_name: name, display_name_source: "generated", admin:)
  end

  def answer(user, score, source: "daily", project: nil, doing_well: "the guide", improve: "more examples", anything_else: nil, created_at: NOW)
    NpsResponse.new(user:, score:, source:, project:, doing_well:, improve:, anything_else:, created_at:)
  end
end
