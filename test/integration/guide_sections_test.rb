require "test_helper"

# A browser reading a guide reports the sections it reached, each once, and
# the server adds one to that day's count for each, for that guide. It
# counts only the guide's own sections, for today or yesterday, and stores
# nothing about who read: no user, no address, no cookie.
class GuideSectionsTest < ActionDispatch::IntegrationTest
  # 1am Eastern on October 7: still October 6 in a browser a moment behind.
  NOW = Time.utc(2026, 10, 7, 5)

  setup { travel_to NOW }

  test "a report adds one reader to each section it names, and only the guide's own sections" do
    report "desktop", "2026-10-07", %w[setup-godot hackatime github]
    assert_response :no_content
    report "desktop", "2026-10-07", %w[setup-godot setup-godot]
    report "clubs", "2026-10-06", %w[setup-godot hackatime pick-project start]
    assert_response :no_content
    assert_equal [ [ Date.new(2026, 10, 6), "clubs", "setup-godot", 1 ], [ Date.new(2026, 10, 6), "clubs", "start", 1 ],
                   [ Date.new(2026, 10, 7), "desktop", "github", 1 ], [ Date.new(2026, 10, 7), "desktop", "hackatime", 1 ],
                   [ Date.new(2026, 10, 7), "desktop", "setup-godot", 2 ] ],
                 GuideSectionDay.order(:day, :guide, :section).pluck(:day, :guide, :section, :readers)
  end

  test "a guide that is not one, a day that is not today or yesterday, or no section of the guide counts nothing" do
    [ [ "guide", "2026-10-07", %w[setup-godot] ], [ "desktop", "2026-10-08", %w[setup-godot] ], [ "desktop", "2026-10-05", %w[setup-godot] ],
      [ "desktop", "2026-02-30", %w[setup-godot] ], [ "desktop", "today", %w[setup-godot] ], [ "desktop", "2026-10-07", %w[ship nope] ],
      [ "desktop", "2026-10-07", [] ] ].each do |guide, day, sections|
      report guide, day, sections
      assert_response :unprocessable_entity, [ guide, day, sections ].inspect
    end
    post guide_sections_path, params: { guide: "desktop", day: "2026-10-07", sections: { "a" => "setup-godot" } }
    assert_response :unprocessable_entity
    assert_equal 0, GuideSectionDay.count
  end

  test "it keeps no trace of the reader, signed in or not" do
    assert_equal %w[day guide id readers section], GuideSectionDay.column_names.sort
    report "new_site", "2026-10-07", %w[movement]
    assert_nil response.headers["Set-Cookie"]
    log_in("participant")
    report "new_site", "2026-10-07", %w[movement]
    assert_equal [ [ "new_site", "movement", 2 ] ], GuideSectionDay.pluck(:guide, :section, :readers)
  end

  test "past the limit an address is turned away, counted by a key that holds no address" do
    # The test cache stores nothing, so it is told the address is past the limit.
    keys = []
    store = GuideSectionsController.cache_store
    store.define_singleton_method(:increment) do |key, *, **|
      keys << key
      GuideSectionsController::RATE + 1
    end
    begin
      post guide_sections_path, params: { guide: "desktop", day: "2026-10-07", sections: %w[movement] }, env: { "REMOTE_ADDR" => "203.0.113.7" }
    ensure
      store.singleton_class.remove_method(:increment)
    end
    assert_response :too_many_requests
    assert_equal 0, GuideSectionDay.count
    assert_equal 1, keys.size
    assert_match(/guide_sections:\h{16}\z/, keys.first)
    assert_not_includes keys.first, "203.0.113.7"
  end

  test "each guide's sections are the headings its pages show, in order" do
    user = log_in("participant")
    get guide_path
    assert_equal GuideSections.find("desktop").sections, css_select("article.guide h2[id], article.guide h3[id]").map { it["id"] } - %w[guide-overview]
    assert_select "article.guide[data-controller~=guide-progress][data-guide-progress-guide-value=desktop]"
    assert_select "head script[type=module]", text: /application\.register\("guide-progress", tracker\)/

    { "stardance" => "stardance", "clubs" => "clubs" }.each do |slug, key|
      ids = GuidePage.all.flat_map do |step|
        get side_guide_path(slug, step)
        css_select(".guide-step h2[id], .guide-step h3[id]").map { it["id"] }
      end
      assert_equal GuideSections.find(key).sections, ids, key
      assert_select ".hub[data-guide-progress-guide-value=?]", key
    end

    user.update!(new_site: true)
    ids = GuidePage.all.flat_map do |step|
      get guide_page_path(step)
      css_select(".guide-step h2[id], .guide-step h3[id]").map { it["id"] }
    end
    assert_equal GuideSections.find("new_site").sections, ids
    assert_select ".hub[data-guide-progress-guide-value=new_site]"
  end

  test "no other page carries the tracker" do
    [ root_path, requirements_path, login_path ].each do |path|
      get path
      assert_no_match(/guide-progress|guide_progress/, response.body, path)
    end
  end

  private

  def report(guide, day, sections) = post guide_sections_path, params: { guide:, day:, sections: }
end
