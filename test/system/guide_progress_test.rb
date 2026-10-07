require "application_system_test_case"

# How far readers get in the desktop's guide and in Stardance's and the
# clubs' guides, in a real browser: a section counts once its heading stays
# in view for a moment while the tab shows, once a browser, and not when the
# reader scrolls past it. A heading stays half a second here, in place of 2.
class GuideProgressTest < ApplicationSystemTestCase
  include GuideProgressTests

  test "the desktop's guide counts each section a reader stays on, once, and none scrolled past or read in a hidden tab" do
    visit guide_path
    assert_selector "article.guide"
    # Under the guide's own list of sections, its first heading sits low.
    scroll_heading "setup-godot"
    wait_for { counted("desktop", "setup-godot") == 1 }

    # A fast scroll past a section does not count it, and staying on one does.
    page.execute_script("document.getElementById('bounce').scrollIntoView(); scrollTo(0, 0)")
    scroll_heading "movement"
    wait_for { counted("desktop", "movement") == 1 }
    assert_equal 0, counted("desktop", "bounce")

    # A hidden tab reads nothing, until it shows again.
    hide_tab(true)
    scroll_heading "drag"
    sleep 1.5
    assert_equal 0, counted("desktop", "drag")
    hide_tab(false)
    wait_for { counted("desktop", "drag") == 1 }

    # Read again, each section counts no more.
    visit guide_path
    scroll_heading "movement"
    sleep 1.5
    assert_equal [ 1, 1, 1 ], %w[setup-godot movement drag].map { counted("desktop", it) }
    assert_equal %w[drag movement setup-godot], (stored("desktop") & %w[setup-godot movement drag bounce]).sort
  end

  test "Stardance's and the clubs' guides each count their own sections" do
    visit "/stardance/move"
    wait_for { counted("stardance", "movement") == 1 }
    visit "/clubs/move"
    wait_for { counted("clubs", "movement") == 1 }
    # Going on to the next step, without a new page, counts its sections too.
    click_on "Animate and drag", match: :first
    assert_current_path "/clubs/animate"
    wait_for { counted("clubs", "animations") == 1 }
    assert_equal [ 1, 0, 0 ], [ counted("stardance", "movement"), counted("stardance", "animations"), counted("desktop", "movement") ]
    assert_includes stored("stardance"), "movement"
    assert_not_includes stored("stardance"), "animations"
  end
end
