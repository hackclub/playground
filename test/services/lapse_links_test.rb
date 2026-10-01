require "test_helper"

# Lapse lookup against canned Hackatime admin and Lapse responses. HttpJson.get is
# swapped for the test; nothing here reaches the network.
class LapseLinksTest < ActiveSupport::TestCase
  HEARTBEATS = {
    "rock-pet-art" => [ { "entity" => "sprites (abc123DEF456)" }, { "entity" => "sprites (abc123DEF456)" }, { "entity" => "walk cycle (zzz999yyy888)" } ],
    "rock-pet" => [ { "entity" => "/Users/me/rock/main.js" } ]
  }.freeze
  TIMELAPSES = {
    "abc123DEF456" => { "name" => "sprites", "duration" => 1800, "visibility" => "UNLISTED" },
    "zzz999yyy888" => { "name" => "walk cycle", "duration" => 600, "visibility" => "FAILED_PROCESSING" }
  }.freeze

  setup do
    @user = User.create!(hca_id: "ident!lapse", hackatime_user_id: "11201")
    @calls = calls = []
    HttpJson.singleton_class.alias_method(:real_get, :get)
    HttpJson.define_singleton_method(:get) do |url, headers: {}, **|
      calls << [ url, headers ]
      if url.start_with?(LapseLinks::HACKATIME)
        project = Rack::Utils.parse_query(URI(url).query)["project"]
        { "heartbeats" => HEARTBEATS.fetch(project, []), "has_more" => false }
      else
        id = Rack::Utils.parse_query(URI(url).query)["id"]
        t = TIMELAPSES[id] or raise HttpJson::Error.new("404", status: 404)
        { "ok" => true, "data" => { "timelapse" => t } }
      end
    end
    LapseLinks.singleton_class.alias_method(:real_key, :key)
    LapseLinks.define_singleton_method(:key) { "hka_test" }
  end

  teardown do
    HttpJson.singleton_class.alias_method(:get, :real_get)
    LapseLinks.singleton_class.alias_method(:key, :real_key)
  end

  test "finds each Lapse once from heartbeats, skips failed ones, and links it" do
    result = LapseLinks.for(@user, %w[rock-pet rock-pet-art])
    assert_nil result.error
    assert_equal [ "abc123DEF456" ], result.lapses.map(&:id)
    assert_equal 1800, result.seconds
    assert_equal [ "https://lapse.hackclub.com/timelapse/abc123DEF456" ], result.urls
    hackatime = @calls.select { it.first.start_with?(LapseLinks::HACKATIME) }
    assert hackatime.all? { it.first.include?("language=Lapse") && it.last["Authorization"] == "Bearer hka_test" }
  end

  test "asks only for Lapse heartbeats inside the program window" do
    ProgramWindow.current = ProgramWindow.load({ starts_at: "2026-09-25 17:00", ends_at: "2026-10-09 17:00" })
    LapseLinks.for(@user, %w[rock-pet-art])
    query = Rack::Utils.parse_query(URI(@calls.first.first).query)
    assert_equal [ Time.utc(2026, 9, 25, 21).to_i, Time.utc(2026, 10, 9, 21).to_i ].map(&:to_s), query.values_at("start_date", "end_date")
  end

  test "without an admin key it says so and guesses nothing" do
    LapseLinks.define_singleton_method(:key) { nil }
    result = LapseLinks.for(@user, %w[rock-pet-art])
    assert_equal "no Hackatime admin key", result.error
    assert_empty result.lapses
    assert_empty @calls
  end

  test "an API failure is reported, not raised" do
    HttpJson.define_singleton_method(:get) { |*, **| raise HttpJson::Error.new("GET -> 500", status: 500) }
    result = LapseLinks.for(@user, %w[rock-pet-art])
    assert_match "could not read Lapses", result.error
  end
end
