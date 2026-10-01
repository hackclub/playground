require "test_helper"

# Coding hours from Hackatime's spans: how spans become seconds per hour, the
# range each refresh asks for, and what a refusal leaves. HttpJson.get is
# swapped for the test, as in HackatimeTest, and the real client is used.
class CodingHoursTest < ActiveSupport::TestCase
  WINDOW = ProgramWindow.load({ starts_at: "2026-09-25 17:00", ends_at: "2026-10-12 09:00" })

  def et(text) = ActiveSupport::TimeZone[ProgramWindow::ZONE].parse(text)
  def span(from, to) = Hackatime::Span.new(start_time: from, end_time: to)
  def bucket(*spans) = CodingHours.bucket(spans, from: WINDOW.starts_at, to: WINDOW.ends_at)
  def epoch(text) = et(text).to_f

  setup do
    ProgramWindow.current = WINDOW
    @real_services = ENV["REAL_SERVICES"]
    ENV["REAL_SERVICES"] = "1"
    @calls = calls = []
    @spans = []
    @statuses = {}
    test = self
    HttpJson.singleton_class.alias_method(:real_get, :get)
    HttpJson.define_singleton_method(:get) do |url, headers: {}, **|
      token = headers["Authorization"].to_s.delete_prefix("Bearer ")
      calls << [ token, url ]
      test.answer(token, URI(url))
    end
  end

  teardown do
    HttpJson.singleton_class.alias_method(:get, :real_get)
    ENV["REAL_SERVICES"] = @real_services
  end

  def answer(token, uri)
    status = @statuses[token]
    raise HttpJson::Error.new("GET #{uri.host}#{uri.path} -> #{status}", status:) if status
    @on_spans&.call if uri.path.end_with?("/spans")
    return { "spans" => @spans.map { { "start_time" => epoch(it[0]), "end_time" => epoch(it[1]) } } } if uri.path.end_with?("/spans")
    { "data" => { "total_seconds" => 5400, "projects" => [], "user_id" => 7 } }
  end

  def spans_queries = @calls.map(&:last).select { URI(it).path.end_with?("/spans") }.map { Rack::Utils.parse_query(URI(it).query) }

  def participant(token = "hka_ok", names: [ "rock-pet" ])
    user = User.create!(hca_id: "ident!ch-#{SecureRandom.hex(3)}", hackatime_access_token: token)
    user.projects.create!(name: "rock", hackatime_projects: names)
    user.reload
  end

  def rows(user) = user.coding_hours.order(:hour).pluck(:hour, :seconds).map { |hour, seconds| [ hour.in_time_zone(ProgramWindow::ZONE).strftime("%m-%d %H:%M"), seconds ] }

  test "a span inside one hour goes into that hour" do
    assert_equal({ et("2026-09-26 10:00").utc => 30 * 60 }, bucket(span(et("2026-09-26 10:05"), et("2026-09-26 10:35"))))
  end

  test "a span across hours goes into each hour by its share" do
    assert_equal [ 20 * 60, 3600, 10 * 60 ], bucket(span(et("2026-09-26 10:40"), et("2026-09-26 12:10"))).values
    assert_equal [ et("2026-09-26 10:00"), et("2026-09-26 11:00"), et("2026-09-26 12:00") ],
                 bucket(span(et("2026-09-26 10:40"), et("2026-09-26 12:10"))).keys
  end

  test "a span across an Eastern midnight splits there too" do
    hours = bucket(span(et("2026-09-26 23:30"), et("2026-09-27 00:45")))
    assert_equal({ et("2026-09-26 23:00") => 30 * 60, et("2026-09-27 00:00") => 45 * 60 }, hours)
    assert_equal [ Time.utc(2026, 9, 27, 3), Time.utc(2026, 9, 27, 4) ], hours.keys, "stored as UTC hours"
  end

  test "only the part inside the window counts" do
    assert_equal({ et("2026-09-25 17:00") => 30 * 60 }, bucket(span(et("2026-09-25 16:30"), et("2026-09-25 17:30"))))
    assert_equal({ et("2026-10-12 08:00") => 30 * 60 }, bucket(span(et("2026-10-12 08:30"), et("2026-10-12 09:30"))))
    assert_empty bucket(span(et("2026-09-25 15:00"), et("2026-09-25 16:59")), span(et("2026-10-12 09:00"), et("2026-10-12 10:00")))
  end

  test "zero-length spans and slivers that round to nothing add no hours" do
    at = et("2026-09-26 10:00")
    assert_empty bucket(span(at, at))
    assert_empty bucket(span(at, at + 0.4))
    assert_equal({ at => 60 }, bucket(span(at, at), span(at, at + 60)))
  end

  test "overlapping spans count their shared time once" do
    hours = bucket(span(et("2026-09-26 10:00"), et("2026-09-26 10:40")), span(et("2026-09-26 10:20"), et("2026-09-26 11:10")),
                   span(et("2026-09-26 10:30"), et("2026-09-26 10:35")))
    assert_equal({ et("2026-09-26 10:00") => 3600, et("2026-09-26 11:00") => 10 * 60 }, hours)
  end

  test "a first sync asks for the whole window so far, with every name in one request" do
    user = participant(names: %w[rock-pet rock-pet-art])
    user.projects.create!(name: "frog", hackatime_projects: [ "frog-widget" ])
    @spans = [ [ "2026-09-26 10:40", "2026-09-26 12:10" ] ]
    travel_to(et("2026-09-28 10:00")) { assert CodingHours.refresh(user) }

    query = spans_queries.sole
    assert_equal %w[2026-09-25T17:00:00-04:00 2026-09-28T10:00:00-04:00], query.values_at("start_date", "end_date")
    assert_equal %w[frog-widget rock-pet rock-pet-art], query["filter_by_project"].split(",").sort
    assert_equal [ [ "09-26 10:00", 20 * 60 ], [ "09-26 11:00", 3600 ], [ "09-26 12:00", 10 * 60 ] ], rows(user)
    assert_equal et("2026-09-28 10:00"), user.reload.coding_hours_synced_at
  end

  test "later syncs ask from the Eastern day before the last sync, an hour early, and replace rows from that day on" do
    user = participant
    user.coding_hours.create!(hour: et("2026-09-26 23:00"), seconds: 600)
    user.coding_hours.create!(hour: et("2026-09-27 15:00"), seconds: 900)
    user.update_columns(coding_hours_synced_at: et("2026-09-28 09:00"))
    # One span crosses the range's start at midnight; another has grown since.
    @spans = [ [ "2026-09-26 23:30", "2026-09-27 00:30" ], [ "2026-09-28 09:10", "2026-09-28 09:40" ] ]
    travel_to(et("2026-09-28 11:00")) { assert CodingHours.refresh(user) }

    query = spans_queries.sole
    assert_equal "2026-09-26T23:00:00-04:00", query["start_date"], "midnight of the 27th, less an hour"
    assert_equal "2026-09-28T11:00:00-04:00", query["end_date"]
    assert_equal [ [ "09-26 23:00", 600 ], [ "09-27 00:00", 30 * 60 ], [ "09-28 09:00", 30 * 60 ] ], rows(user),
                 "the 26th is kept as it was, the vanished 15:00 row is gone, and only the part from midnight on is written"
  end

  test "a sync never asks before the window opens or past its end" do
    user = participant
    user.update_columns(coding_hours_synced_at: et("2026-09-25 20:00"))
    @spans = [ [ "2026-09-25 16:00", "2026-09-25 17:30" ] ] # a span from before the window, as if Hackatime sent one
    travel_to(et("2026-09-26 08:00")) { CodingHours.refresh(user) }
    assert_equal [ [ "09-25 17:00", 30 * 60 ] ], rows(user)
    user.update_columns(coding_hours_synced_at: et("2026-10-11 20:00"))
    travel_to(et("2026-10-14 12:00")) { CodingHours.refresh(user) }
    assert_equal [ %w[2026-09-25T17:00:00-04:00 2026-09-26T08:00:00-04:00], %w[2026-10-09T23:00:00-04:00 2026-10-12T09:00:00-04:00] ],
                 spans_queries.map { it.values_at("start_date", "end_date") }
    assert_equal et("2026-10-14 12:00"), user.reload.coding_hours_synced_at

    fresh = participant
    travel_to(et("2026-09-25 16:00")) { assert_not CodingHours.refresh(fresh), "the program hasn't started" }
    assert_equal 2, spans_queries.size
  end

  test "Hackatime refusing or failing leaves the rows and the sync time as they were" do
    { "hka_revoked" => 401, "hka_banned" => 403, "hka_down" => 500 }.each do |token, status|
      user = participant(token)
      user.coding_hours.create!(hour: et("2026-09-27 15:00"), seconds: 900)
      user.update_columns(coding_hours_synced_at: et("2026-09-28 09:00"))
      @statuses[token] = status
      travel_to(et("2026-09-28 11:00")) { assert_not CodingHours.refresh(user), "#{status} is skipped" }
      assert_equal [ [ "09-27 15:00", 900 ] ], rows(user), "#{status} keeps the rows"
      assert_equal et("2026-09-28 09:00"), user.reload.coding_hours_synced_at
      assert_equal 0, user.projects.sole.tracked_seconds, "#{status} asks for no totals"
    end
  end

  test "names come from every pet and every ship that claimed time, and nothing is asked without names" do
    user = participant(names: %w[rock-pet rock-pet-art])
    pet = user.projects.sole
    pet.ships.create!(user:, claimed_seconds: 60, snapshot: { "hackatime_projects" => [ "rock-pet" ], "projects" => { "rock-pet-art" => 60 } })
    returned = user.projects.create!(name: "frog", hackatime_projects: [ "frog-widget", "frog-art" ])
    returned.ships.create!(user:, claimed_seconds: 60, state: "changes_needed", snapshot: { "hackatime_projects" => [ "frog-art" ] })
    pet.update!(hackatime_projects: [])
    returned.update!(hackatime_projects: [ "frog-widget" ])
    assert_equal %w[frog-widget rock-pet rock-pet-art], CodingHours.hackatime_names(user.reload).sort,
                 "shipped names stay after unlinking; a ship sent back for changes claimed nothing"

    empty = participant(names: [])
    empty.coding_hours.create!(hour: et("2026-09-27 15:00"), seconds: 900)
    travel_to(et("2026-09-28 11:00")) { assert CodingHours.refresh(empty) }
    assert_empty spans_queries
    assert_empty rows(empty)
  end

  test "each pet's tracked total is refreshed in the same pass" do
    user = participant
    user.projects.sole.update_columns(tracked_seconds: 60, tracked_at: 1.minute.ago)
    travel_to(et("2026-09-28 11:00")) { CodingHours.refresh(user) }
    pet = user.projects.sole.reload
    assert_equal 5400, pet.tracked_seconds, "refreshed even though it was fresh"
    assert_equal et("2026-09-28 11:00"), pet.tracked_at
  end

  test "changing a pet's Hackatime projects has the next sync ask for the whole window again" do
    user = participant
    travel_to(et("2026-09-28 10:00")) { CodingHours.refresh(user) }
    assert_not_nil user.reload.coding_hours_synced_at
    user.projects.sole.update!(name: "renamed")
    assert_not_nil user.reload.coding_hours_synced_at, "other edits keep it"

    user.projects.sole.update!(hackatime_projects: %w[rock-pet rock-pet-art])
    assert_nil user.reload.coding_hours_synced_at
    travel_to(et("2026-09-28 11:00")) { CodingHours.refresh(user) }
    assert_equal "2026-09-25T17:00:00-04:00", spans_queries.last["start_date"]

    user.projects.sole.destroy!
    assert_nil user.reload.coding_hours_synced_at, "a deleted pet takes its time away"
  end

  test "a reset during a sync is not overwritten" do
    user = participant
    user.update_columns(coding_hours_synced_at: et("2026-09-28 09:00"))
    pet = user.projects.sole
    @on_spans = -> { pet.update!(hackatime_projects: %w[rock-pet new]) }
    travel_to(et("2026-09-28 11:00")) { CodingHours.refresh(user) }
    assert_nil user.reload.coding_hours_synced_at, "the next sync asks for the whole window"
  end
end
