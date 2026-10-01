require "application_system_test_case"

# The admin's nav keys: 4 opens people and 5 opens stats, as 1 to 3 open the
# queues. A key typed into a field is only typing.
class AdminShortcutsTest < ApplicationSystemTestCase
  setup do
    # A short window keeps the stats page's signup chart to a few days.
    ProgramWindow.current = ProgramWindow.new(starts_at: 3.days.ago, ends_at: 10.days.from_now)
    visit dev_login_path(as: "admin", admin: 1)
    assert_selector ".adminnav"
  end

  test "4 opens people and 5 opens stats" do
    assert_selector ".adminnav a", text: "people"
    assert_selector ".adminnav kbd", text: "4"
    assert_selector ".adminnav kbd", text: "5"
    find("body").send_keys("4")
    assert_current_path admin_people_path
    find("body").send_keys("5")
    assert_current_path admin_stats_path
    assert_selector "h2", text: "where do people drop out?"
    find("body").send_keys("4")
    assert_current_path admin_people_path
  end

  test "5 and 4 typed into the search field stay in the field" do
    visit admin_people_path
    fill_in "q", with: "54"
    click_button "search"
    assert_current_path "/admin/people?q=54"
    assert_field "q", with: "54"
  end
end
