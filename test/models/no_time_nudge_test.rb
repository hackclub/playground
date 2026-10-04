require "test_helper"

class NoTimeNudgeTest < ActiveSupport::TestCase
  WINDOW = ProgramWindow.load({ starts_at: "2026-09-25 17:00", ends_at: "2026-10-12 09:00" })

  def et(text) = ActiveSupport::TimeZone[ProgramWindow::ZONE].parse(text)

  setup do
    ProgramWindow.current = WINDOW
    @env = ENV.to_h.slice("NO_TIME_NUDGE", "NO_TIME_NUDGE_TEST_EMAILS")
    ENV["NO_TIME_NUDGE"] = "1"
    ENV.delete("NO_TIME_NUDGE_TEST_EMAILS")
    @now = et("2026-10-04 12:00")
  end

  teardown do
    ENV.delete("NO_TIME_NUDGE")
    ENV.delete("NO_TIME_NUDGE_TEST_EMAILS")
    ENV.update(@env)
  end

  def participant(name, signed_up: @now - 4.days, **attrs)
    User.create!(hca_id: "ident!nudge-#{name}", email: "#{name}@example.com", created_at: signed_up, **attrs)
  end

  def run_at(now = @now) = NoTimeNudge.run(now:, window: WINDOW)

  test "marks a participant 72 hours after signup with no ship and no time, and their row syncs next" do
    idle = participant("idle")
    idle.update_column(:synced_at, @now - 1.hour)
    assert_equal 1, run_at
    idle.reload
    assert_equal @now, idle.no_time_nudge_at
    assert_nil idle.synced_at
    assert_equal "yes", AirtableFields.user(idle)["Loops - playgroundNoTimeNudge"]
  end

  test "waits the full 72 hours" do
    fresh = participant("fresh", signed_up: @now - 71.hours)
    assert_equal 0, run_at
    assert_nil fresh.reload.no_time_nudge_at
    run_at(@now + 1.hour)
    assert_not_nil fresh.reload.no_time_nudge_at
  end

  test "skips anyone with a ship, coding time, tracked time, or a ban" do
    shipped = participant("shipped")
    shipped.projects.create!(name: "pet").ships.create!(user: shipped)
    coded = participant("coded")
    coded.coding_hours.create!(hour: @now.utc.beginning_of_hour - 3.hours, seconds: 60)
    tracked = participant("tracked")
    tracked.projects.create!(name: "pet", tracked_seconds: 60)
    participant("banned", banned_at: @now - 1.day)
    assert_equal 0, run_at
  end

  test "waits for a fresh coding hours sync when Hackatime is linked" do
    stale = participant("stale", hackatime_access_token: "hka", coding_hours_synced_at: @now - 3.hours)
    never = participant("never", hackatime_access_token: "hkb")
    synced = participant("synced", hackatime_access_token: "hkc", coding_hours_synced_at: @now - 30.minutes)
    assert_equal 1, run_at
    assert_equal [ synced.id ], User.where.not(no_time_nudge_at: nil).ids
    assert_nil stale.reload.no_time_nudge_at
    assert_nil never.reload.no_time_nudge_at
  end

  test "marks a participant once and keeps the first mark" do
    idle = participant("once")
    run_at
    assert_equal 0, run_at(@now + 1.hour)
    assert_equal @now, idle.reload.no_time_nudge_at
  end

  test "marks nobody outside the program window" do
    late = participant("late")
    assert_equal 0, run_at(WINDOW.ends_at)
    assert_equal 0, run_at(WINDOW.starts_at - 1.minute)
    assert_nil late.reload.no_time_nudge_at
  end

  test "while off, marks nobody but the test emails, which skip the wait" do
    ENV.delete("NO_TIME_NUDGE")
    ENV["NO_TIME_NUDGE_TEST_EMAILS"] = " Tester@example.com ,other@example.com"
    idle = participant("idle")
    tester = participant("tester", signed_up: @now - 1.minute)
    assert_equal 1, run_at
    assert_nil idle.reload.no_time_nudge_at
    assert_not_nil tester.reload.no_time_nudge_at
  end

  test "a test email with a ship is still skipped" do
    ENV["NO_TIME_NUDGE_TEST_EMAILS"] = "tester@example.com"
    tester = participant("tester", signed_up: @now - 1.minute)
    tester.projects.create!(name: "pet").ships.create!(user: tester)
    assert_equal 0, run_at
  end

  test "an unmarked row writes no nudge field" do
    assert_not AirtableFields.user(participant("plain")).key?("Loops - playgroundNoTimeNudge")
  end
end
