require "application_system_test_case"

# How far readers get in the new site's guide, in a real browser: each step's
# sections count once a browser, on that guide alone, signed in or not, and
# with nothing about who.
class NewSiteGuideProgressTest < ApplicationSystemTestCase
  include NewSiteTests
  include GuideProgressTests

  test "the new site's guide counts the sections of each step a reader stays on, once" do
    visit dev_login_path(as: "participant")
    assert_selector "#guide"
    visit guide_page_path("move")
    wait_for { counted("new_site", "movement") == 1 }
    click_on "Animate and drag", match: :first
    assert_current_path "/guide/animate"
    wait_for { counted("new_site", "animations") == 1 }
    visit guide_page_path("move")
    sleep 1.5
    assert_equal [ 1, 1, 0 ], [ counted("new_site", "movement"), counted("new_site", "animations"), counted("desktop", "movement") ]
    assert_equal %w[day guide id readers section], GuideSectionDay.column_names.sort
  end
end
