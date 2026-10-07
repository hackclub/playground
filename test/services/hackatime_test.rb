require "test_helper"

# Hackatime's answers against canned responses: the program window it is
# asked for, and a token it no longer takes. HttpJson.get is swapped for the
# test; nothing reaches the network. The fake is checked against the window.
class HackatimeTest < ActiveSupport::TestCase
  WINDOW = ProgramWindow.load({ starts_at: "2026-09-25 17:00", ends_at: "2026-10-09 17:00" })

  setup do
    @answer = nil
    @urls = urls = []
    answer = -> { @answer }
    HttpJson.singleton_class.alias_method(:real_get, :get)
    HttpJson.define_singleton_method(:get) do |url, **|
      urls << url
      status = answer.call
      status.is_a?(Hash) ? status : raise(HttpJson::Error.new("GET #{URI(url).host}#{URI(url).path} -> #{status}", status:))
    end
  end

  def query(url) = Rack::Utils.parse_query(URI(url).query)

  test "both calls ask for the window only, as times with the Eastern offset" do
    ProgramWindow.current = WINDOW
    client = Hackatime.new("hka_ok")
    @answer = { "projects" => [ { "name" => "rock-pet", "total_seconds" => 60, "most_recent_heartbeat" => "2026-09-26T10:00:00Z" } ] }
    assert_equal [ "rock-pet" ], client.projects.map(&:name)
    @answer = { "data" => { "total_seconds" => 60, "projects" => [], "user_id" => 7 } }
    client.stats([ "rock-pet", "rock-pet-art" ])

    projects, stats = @urls
    assert_equal "/api/v1/authenticated/projects", URI(projects).path
    assert_equal({ "start_date" => "2026-09-25T17:00:00-04:00", "end_date" => "2026-10-09T17:00:00-04:00" }, query(projects))
    assert_equal "/api/v1/users/my/stats", URI(stats).path
    assert_equal({ "features" => "projects", "start_date" => "2026-09-25T17:00:00-04:00", "end_date" => "2026-10-09T17:00:00-04:00",
                   "filter_by_project" => "rock-pet,rock-pet-art" }, query(stats))
  end

  test "the fake counts only the part of each stretch inside the window" do
    ProgramWindow.current = WINDOW
    fake = Hackatime::Fake.new(User.create!(hca_id: "ident!fake-window", hackatime_access_token: "fake"))
    rock = fake.catalog.first.total_seconds
    pets = %w[rock-pet rock-pet-art]

    travel_to(WINDOW.starts_at - 1.minute) do
      assert_empty fake.projects, "nothing before 5pm on the first day"
      assert_equal 0, fake.stats(pets).total_seconds
    end
    travel_to(WINDOW.starts_at + 1.hour) do
      # rock-pet's stretch began before 5pm; only its last 55 minutes count.
      assert_equal [ "rock-pet" ], fake.projects.map(&:name)
      assert_equal 55 * 60, fake.stats(pets).total_seconds
      assert_equal({ "rock-pet" => 55 * 60 }, fake.stats(pets).projects)
    end
    travel_to(WINDOW.ends_at - 1.minute) do
      assert_equal %w[rock-pet rock-pet-art frog-widget], fake.projects.map(&:name), "the last day counts up to 5pm"
      assert_equal rock + 50 * 60, fake.stats(pets).total_seconds
    end
    travel_to(WINDOW.ends_at + 1.hour) do
      # Its last 55 minutes fell after 5pm on the last day.
      assert_equal rock - 55 * 60 + 50 * 60, fake.stats(pets).total_seconds
      assert_equal WINDOW.ends_at, fake.projects.first.most_recent_heartbeat
    end
    travel_to(WINDOW.ends_at + 5.hours) do
      assert_equal 0, fake.stats(pets).total_seconds, "nothing after the end"
      assert_equal [ "frog-widget" ], fake.projects.map(&:name)
    end
  end

  test "spans ask for the named projects over the range, with the Eastern offset, and answer Times" do
    client = Hackatime.new("hka_ok")
    start = Time.utc(2026, 9, 26, 14)
    @answer = { "spans" => [ { "start_time" => start.to_f, "end_time" => start.to_f + 2220.5, "duration" => 2220.5 } ] }
    spans = client.spans(%w[rock-pet rock-pet-art], from: Time.utc(2026, 9, 26, 4), to: Time.utc(2026, 9, 27, 4))

    assert_equal "/api/v1/users/my/heartbeats/spans", URI(@urls.sole).path
    assert_equal({ "start_date" => "2026-09-26T00:00:00-04:00", "end_date" => "2026-09-27T00:00:00-04:00",
                   "filter_by_project" => "rock-pet,rock-pet-art" }, query(@urls.sole))
    assert_equal [ Hackatime::Span.new(start_time: start, end_time: start + 2220.5) ], spans
    assert_empty client.spans([], from: start, to: start + 1.hour), "no names, no request: Hackatime would answer every project"
    assert_equal 1, @urls.size
  end

  test "the fake's spans are its stretches cut to the range, and over the window add up to its stats" do
    ProgramWindow.current = WINDOW
    fake = Hackatime::Fake.new(User.create!(hca_id: "ident!fake-spans", hackatime_access_token: "fake"))
    pets = %w[rock-pet rock-pet-art]
    [ WINDOW.starts_at + 1.hour, WINDOW.starts_at + 3.days, WINDOW.ends_at - 1.minute, WINDOW.ends_at + 1.hour ].each do |now|
      travel_to(now) do
        spans = fake.spans(pets, from: WINDOW.starts_at, to: WINDOW.ends_at)
        assert_equal fake.stats(pets).total_seconds, spans.sum { (it.end_time - it.start_time).round }, "at #{now}"
      end
    end
    travel_to(WINDOW.starts_at + 1.hour) do
      assert_equal [ [ WINDOW.starts_at, WINDOW.starts_at + 55.minutes ] ],
                   fake.spans(pets, from: WINDOW.starts_at, to: WINDOW.ends_at).map { [ it.start_time, it.end_time ] }
      assert_empty fake.spans([ "frog-widget" ], from: WINDOW.starts_at, to: WINDOW.ends_at)
    end
  end

  teardown { HttpJson.singleton_class.alias_method(:get, :real_get) }

  test "401 and 404 mean Hackatime can't see the account through this token" do
    client = Hackatime.new("hka_revoked")
    spans = -> { client.spans([ "rock-pet" ], from: 1.day.ago, to: Time.current) }
    [ [ 401, -> { client.projects } ], [ 404, -> { client.stats([ "rock-pet" ]) } ], [ 401, spans ], [ 404, spans ] ].each do |status, call|
      @answer = status
      error = assert_raises(Hackatime::Unlinked) { call.call }
      assert_equal status, error.status
      assert_kind_of HttpJson::Error, error, "callers that rescue HttpJson::Error still catch it"
    end
  end

  test "an outage, or a banned Hackatime account, is still a plain error" do
    @answer = 503
    error = assert_raises(HttpJson::Error) { Hackatime.new("hka_ok").stats([]) }
    assert_not_kind_of Hackatime::Unlinked, error
    @answer = 403
    error = assert_raises(HttpJson::Error) { Hackatime.new("hka_banned").spans([ "rock-pet" ], from: 1.day.ago, to: Time.current) }
    assert_not_kind_of Hackatime::Unlinked, error
    assert_equal 403, error.status
  end

  test "the fake refuses a token of revoked" do
    user = User.create!(hca_id: "ident!fake-revoked", hackatime_access_token: "revoked")
    assert_raises(Hackatime::Unlinked) { Hackatime::Fake.new(user).projects }
    assert_raises(Hackatime::Unlinked) { Hackatime::Fake.new(user).stats([]) }
    assert_raises(Hackatime::Unlinked) { Hackatime::Fake.new(user).spans([ "rock-pet" ], from: 1.day.ago, to: Time.current) }
  end

  LAST = Hackatime::IGNORED_PROJECTS.first

  test "the last-project placeholder is left out of the project list, the stats, and the spans" do
    ProgramWindow.current = WINDOW
    client = Hackatime.new("hka_ok")
    @answer = { "projects" => [ { "name" => LAST, "total_seconds" => 600, "most_recent_heartbeat" => "2026-09-26T10:00:00Z" },
                                { "name" => "rock-pet", "total_seconds" => 60, "most_recent_heartbeat" => "2026-09-26T09:00:00Z" } ] }
    assert_equal [ "rock-pet" ], client.projects.map(&:name)

    @answer = { "data" => { "total_seconds" => 60, "projects" => [ { "name" => LAST, "total_seconds" => 600 }, { "name" => "rock-pet", "total_seconds" => 60 } ],
                            "user_id" => 7 } }
    stats = client.stats([ LAST, "rock-pet" ])
    assert_equal({ "rock-pet" => 60 }, stats.projects)
    assert_equal "rock-pet", query(@urls.last)["filter_by_project"]

    @urls.clear
    assert_equal 0, client.stats([ LAST ]).total_seconds, "a pet that links only the placeholder counts nothing"
    assert_nil query(@urls.last)["filter_by_project"]

    @urls.clear
    assert_empty client.spans([ LAST ], from: WINDOW.starts_at, to: WINDOW.starts_at + 1.hour)
    assert_empty @urls, "no request for the placeholder alone"
    @answer = { "spans" => [] }
    client.spans([ LAST, "rock-pet" ], from: WINDOW.starts_at, to: WINDOW.starts_at + 1.hour)
    assert_equal "rock-pet", query(@urls.last)["filter_by_project"]
  end

  test "the fake lists the placeholder nowhere and counts no time on it" do
    ProgramWindow.current = WINDOW
    fake = Hackatime::Fake.new(User.create!(hca_id: "ident!fake-last", hackatime_access_token: "fake"))
    assert_includes fake.catalog.map(&:name), LAST, "the fake has it, as Hackatime does"
    travel_to(WINDOW.ends_at - 1.minute) do
      assert_not_includes fake.projects.map(&:name), LAST
      assert_equal fake.stats([ "rock-pet" ]).total_seconds, fake.stats([ "rock-pet", LAST ]).total_seconds
      assert_not_includes fake.stats([ "rock-pet", LAST ]).projects.keys, LAST
      assert_empty fake.spans([ LAST ], from: WINDOW.starts_at, to: WINDOW.ends_at)
    end
  end

  test "ignored? matches the placeholder whatever its case or edge spaces" do
    assert Hackatime.ignored?("<<LAST_PROJECT>>")
    assert Hackatime.ignored?(" <<last_project>> ")
    assert_not Hackatime.ignored?("last-project")
    assert_equal %w[a b], Hackatime.keep([ "a", LAST, "b" ])
  end
end
