require "test_helper"

# A browser that read Stardance's or the clubs' guide long enough on a US
# Eastern day says so once, and the server adds one to that day's count for
# that guide. It stores the count and nothing about who: no user, no
# address, no cookie.
class GuideReadersTest < ActionDispatch::IntegrationTest
  # 1am Eastern on October 7: still October 6 in the guide for half an hour
  # more, since the browser's day can be a moment behind.
  NOW = Time.utc(2026, 10, 7, 5)

  setup { travel_to NOW }

  test "each report adds one reader to the day and guide, and nothing else" do
    post guide_readers_path, params: { guide: "stardance", day: "2026-10-07" }, as: :json
    assert_response :no_content
    post guide_readers_path, params: { guide: "stardance", day: "2026-10-07" }, as: :json
    post guide_readers_path, params: { guide: "clubs", day: "2026-10-07" }, as: :json
    # Yesterday too, for a reader whose day ended a moment ago.
    post guide_readers_path, params: { guide: "clubs", day: "2026-10-06" }, as: :json
    assert_response :no_content
    assert_equal [ [ Date.new(2026, 10, 6), "clubs", 1 ], [ Date.new(2026, 10, 7), "clubs", 1 ], [ Date.new(2026, 10, 7), "stardance", 2 ] ],
                 GuideReaderDay.order(:day, :guide).pluck(:day, :guide, :readers)
    assert_equal({ Date.new(2026, 10, 7) => { "clubs" => 1, "stardance" => 2 } }, GuideReaderDay.per_day([ Date.new(2026, 10, 7) ]))
  end

  test "a guide that is not one, or a day that is not today or yesterday, counts nothing" do
    [ { guide: "playground", day: "2026-10-07" }, { guide: "stardance", day: "2026-10-08" }, { guide: "stardance", day: "2026-10-05" },
      { guide: "stardance", day: "2026-02-30" }, { guide: "stardance", day: "today" }, { guide: "stardance" }, {} ].each do |params|
      post guide_readers_path, params:, as: :json
      assert_response :unprocessable_entity, params.inspect
    end
    assert_equal 0, GuideReaderDay.count
  end

  test "it keeps no trace of the reader, signed in or not" do
    assert_equal %w[day guide id readers], GuideReaderDay.column_names.sort
    post guide_readers_path, params: { guide: "clubs", day: "2026-10-07" }, as: :json
    assert_nil response.headers["Set-Cookie"]
    log_in("participant")
    post guide_readers_path, params: { guide: "clubs", day: "2026-10-07" }, as: :json
    assert_equal [ [ "clubs", 2 ] ], GuideReaderDay.pluck(:guide, :readers)
  end

  test "the rate limit counts a keyed hash of the address and the day, never the address" do
    controller = GuideReadersController.new
    controller.request = ActionDispatch::TestRequest.create("REMOTE_ADDR" => "203.0.113.7")
    key = controller.send(:anonymous_key)
    assert_match(/\A\h{16}\z/, key)
    assert_not_includes key, "203"
    controller.request = ActionDispatch::TestRequest.create("REMOTE_ADDR" => "203.0.113.8")
    assert_not_equal key, controller.send(:anonymous_key)
    travel 1.day
    controller.request = ActionDispatch::TestRequest.create("REMOTE_ADDR" => "203.0.113.7")
    assert_not_equal key, controller.send(:anonymous_key), "a new key each day"
  end
end
