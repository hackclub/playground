require "application_system_test_case"

# A signed-in reader's journey through the new site's guide, in a real
# browser: each step's sections count once a browser, on that guide alone,
# and nothing about who.
class NewSiteGuideJourneyTest < ApplicationSystemTestCase
  include NewSiteTests
  include GuideProgressTests

  test "the new site's guide counts a reader's journey through its steps once, with nothing about who" do
    visit "/requirements"
    page.execute_script("localStorage.clear()")
    visit dev_login_path(as: "participant")
    assert_selector "#guide"
    visit guide_page_path("move")
    wait_for { journey("new_site")[[ "movement", 0 ]] == 1 }
    click_on "Animate and drag", match: :first
    assert_current_path "/guide/animate"
    wait_for { journey("new_site")[[ "animations", 0 ]] == 1 }
    visit guide_page_path("move")
    sleep 1.5
    assert_equal [ 1 ], journey("new_site").values.uniq
    assert_equal [ [ "direct", "", "", "direct" ] ], journey_sources("new_site")
    assert_equal 0, GuideJourneyDay.where.not(guide: "new_site").count
    assert_equal %w[day first_campaign first_medium first_source guide id last_campaign last_medium last_source minutes readers stage],
                 GuideJourneyDay.column_names.sort
  end
end
