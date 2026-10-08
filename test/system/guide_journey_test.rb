require "application_system_test_case"

# A reader's journey through the desktop's guide, Stardance's, and the
# clubs', in a real browser: opening the guide, each section reached, and
# engaged time in buckets, counted once a browser, with where the reader
# came from. Time stops in a hidden tab and when the reader does nothing.
# Here a "minute" is a second, and time stops 2 seconds after the reader
# last did anything.
class GuideJourneyTest < ApplicationSystemTestCase
  include GuideProgressTests

  setup do
    visit "/requirements"
    page.execute_script("localStorage.clear()")
  end

  test "the desktop's guide counts a reader's journey once, with the tagged link they came from" do
    visit "/guide?utm_source=Newsletter&utm_medium=email&utm_campaign=October"
    assert_selector "article.guide"
    wait_for { journey("desktop")[[ "opened", 0 ]] == 1 }
    assert_equal [ [ "newsletter", "email", "october", "newsletter" ] ], journey_sources("desktop")

    scroll_heading "setup-godot"
    wait_for { journey("desktop")[[ "setup-godot", 0 ]] == 1 }
    # Reading on past two "minutes" moves the reader into the next bucket.
    8.times { nudge && sleep(0.4) }
    wait_for { journey("desktop")[[ "setup-godot", 2 ]] == 1 }

    # Read again, the browser counts no more.
    visit guide_path
    scroll_heading "setup-godot"
    sleep 1.5
    assert_equal [ 1 ], journey("desktop").values.uniq
    assert_equal "setup-godot", kept_journey("desktop")["sent"]["stage"]
  end

  test "time stops while the tab is hidden, even with activity, and a couple of seconds after the reader stops" do
    visit "/clubs/move"
    wait_for { kept_journey("clubs")&.dig("seconds").to_f > 0.5 }
    hide_tab(true)
    hidden = kept_journey("clubs")["seconds"]
    5.times { nudge && sleep(0.3) }
    sleep 1
    assert_in_delta hidden, kept_journey("clubs")["seconds"], 0.001

    # Showing again counts as activity, then nothing: 2 seconds count.
    hide_tab(false)
    sleep 4.5
    assert_in_delta hidden + 2, kept_journey("clubs")["seconds"], 0.35
  end

  test "Stardance's and the clubs' guides each count their own journeys, from the guide the first visit started on" do
    visit "/stardance/move"
    wait_for { journey("stardance")[[ "movement", 0 ]] == 1 }
    assert_equal [ [ "stardance", "direct", "", "stardance" ] ], journey_sources("stardance")
    # A typed visit to the clubs' guide is direct, so both touches stay.
    visit "/clubs/move"
    wait_for { journey("clubs")[[ "movement", 0 ]] == 1 }
    assert_equal [ [ "stardance", "direct", "", "stardance" ] ], journey_sources("clubs")
    # Reaching a section counts every stage before it, as the reader got this far.
    assert_equal 1, journey("clubs")[[ "setup-godot", 0 ]]
    assert_nil journey("clubs")[[ "animations", 0 ]]
    assert_equal 0, GuideJourneyDay.where(guide: "desktop").count
  end
end
