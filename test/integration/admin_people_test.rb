require "test_helper"

# The people table: each person's approved, pending, and unshipped hours, in
# the same few queries however many people it lists.
class AdminPeopleTest < ActionDispatch::IntegrationTest
  setup do
    @admin = log_in("admin")
  end

  test "the table shows unshipped hours after pending" do
    user = participant(1)
    get admin_people_path
    assert_equal [ "who", "full name", "status", "approved", "pending", "unshipped", "joined" ], css_select("table.list th").map(&:text)
    row = css_select("table.list tr").find { it.text.include?(user.email) }
    # 3h tracked: 1h shipped and waiting, 2h unshipped.
    assert_equal [ "0m", "1h 0m", "2h 0m" ], row.css("td")[3, 3].map(&:text)
  end

  test "listing more people takes no more queries" do
    2.times { participant(it) }
    # The first page saves the admin's new display name.
    get admin_people_path
    few = queries { get admin_people_path }
    (2...8).each { participant(it) }
    assert_equal few, queries { get admin_people_path }
    assert_select "table.list tr", 10
  end

  private

  def participant(i)
    user = User.create!(hca_id: "ident!people-#{i}", email: "p#{i}@example.com", display_name: "person #{i}", display_name_source: "generated")
    pet = user.projects.create!(name: "pet #{i}", hackatime_projects: [ "pet-#{i}" ], tracked_seconds: 3 * 3600)
    pet.ships.create!(user:, claimed_seconds: 3600)
    user
  end

  # Queries a block makes, the query cache off so a repeat still counts.
  def queries
    count = 0
    counter = ->(*, payload) { count += 1 unless payload[:name].in?(%w[SCHEMA TRANSACTION]) }
    ActiveRecord::Base.uncached { ActiveSupport::Notifications.subscribed(counter, "sql.active_record") { yield } }
    count
  end
end
