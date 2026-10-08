require "test_helper"

# A browser reports its journey through a guide: the guide, the day it
# started, where it came from, where it was and where it is now. The server
# adds one to each count the browser newly belongs to, takes only the
# guide's own stages and the buckets, moving forward, for a start day a
# browser could have, and keeps nothing about who.
class GuideJourneysTest < ActionDispatch::IntegrationTest
  # 1am Eastern on October 8.
  NOW = Time.utc(2026, 10, 8, 5)
  SOURCES = { first_source: "clubs", first_medium: "email", first_campaign: "launch", last_source: "slack", last_medium: "referral", last_campaign: "" }.freeze

  setup { travel_to NOW }

  test "a first report counts where the browser is, and the next only what is new" do
    report to: [ "setup-godot", "2" ]
    assert_response :no_content
    report from: [ "setup-godot", "2" ], to: [ "github", "2" ]
    assert_response :no_content
    assert_equal [ [ "github", 0 ], [ "github", 2 ], [ "opened", 0 ], [ "opened", 2 ], [ "setup-godot", 0 ], [ "setup-godot", 2 ] ],
                 GuideJourneyDay.order(:stage, :minutes).pluck(:stage, :minutes)
    assert_equal [ [ Date.new(2026, 10, 7), "clubs", 1, "clubs", "email", "launch", "slack", "referral", "" ] ],
                 GuideJourneyDay.distinct.pluck(:day, :guide, :readers, *SOURCES.keys)
  end

  test "a guide, stage, bucket, or day that does not fit, or a step back, counts nothing" do
    [ { guide: "nope" }, { to: [ "hackatime", "0" ] }, { to: [ "opened", "3" ] }, { to: [ "opened", "x" ] }, { to: [ "opened", "" ] },
      { day: "2026-10-10" }, { day: "2026-06-09" }, { day: "today" }, { day: "2026-02-30" },
      { from: [ "github", "5" ], to: [ "setup-godot", "5" ] }, { from: [ "github", "5" ], to: [ "sync", "2" ] },
      { from: [ "nowhere", "0" ], to: [ "github", "0" ] }, { from: [ nil, "0" ], to: [ "github", "0" ] } ].each do |bad|
      report(**bad)
      assert_response :unprocessable_entity, bad.inspect
    end
    post guide_journeys_path, params: { guide: "clubs", day: "2026-10-07", to_stage: [ "opened" ], to_minutes: "0" }
    assert_response :unprocessable_entity
    assert_equal 0, GuideJourneyDay.count
  end

  test "a day the journey could have started on counts: up to 120 days back, and tomorrow for a clock ahead" do
    [ "2026-10-08", "2026-10-09", "2026-06-10" ].each do |day|
      report(day:)
      assert_response :no_content, day
    end
    assert_equal [ Date.new(2026, 6, 10), Date.new(2026, 10, 8), Date.new(2026, 10, 9) ], GuideJourneyDay.distinct.order(:day).pluck(:day)
  end

  test "sources are cleaned, junk is other, and a report with none is unknown" do
    report(sources: { first_source: "<b>Clubs</b>", first_medium: "E Mail", first_campaign: "x" * 41, last_source: "", last_medium: "", last_campaign: "" })
    assert_equal [ [ "other", "e-mail", "other", "unknown", "", "" ] ], GuideJourneyDay.distinct.pluck(*SOURCES.keys)
  end

  test "it keeps no trace of the reader, signed in or not, and is never logged" do
    report
    assert_nil response.headers["Set-Cookie"]
    log_in("participant")
    report
    assert_equal [ 2 ], GuideJourneyDay.distinct.pluck(:readers)
    assert_not GuideJourneyDay.column_names.any? { it.match?(/user|ip|address|cookie|session|browser|agent/) }
    silencer = Rails.application.middleware.find { it.klass == Rails::Rack::SilenceRequest }
    assert silencer, "the anonymous counts are silenced"
    path = silencer.args.first[:path]
    assert(%w[/guide_journeys /guide_sections /guide_readers].all? { path.match?(it) })
    assert_no_match path, "/guide_journeys/x"
    stack = Rails.application.middleware.map(&:klass)
    assert_operator stack.index(Rails::Rack::SilenceRequest), :<, stack.index(Rails::Rack::Logger)
  end

  test "past the limit an address is turned away, counted by a key that holds no address" do
    keys = []
    store = GuideJourneysController.cache_store
    store.define_singleton_method(:increment) do |key, *, **|
      keys << key
      GuideJourneysController::RATE + 1
    end
    begin
      report(env: { "REMOTE_ADDR" => "203.0.113.7" })
    ensure
      store.singleton_class.remove_method(:increment)
    end
    assert_response :too_many_requests
    assert_equal 0, GuideJourneyDay.count
    assert_match(/guide_journeys:\h{16}\z/, keys.first)
    assert_not_includes keys.first, "203.0.113.7"
  end

  private

  def report(guide: "clubs", day: "2026-10-07", from: nil, to: [ "opened", "0" ], sources: SOURCES, env: {})
    params = { guide:, day:, to_stage: to[0], to_minutes: to[1], **sources }
    params.merge!(from_stage: from[0], from_minutes: from[1]) if from
    post guide_journeys_path, params: params.compact, env:
  end
end
