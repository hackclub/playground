require "test_helper"

# The hourly refresh of every participant's coding hours, against canned
# Hackatime answers: HttpJson.get is swapped for the test, as in
# HackatimeTest.
class CodingHoursJobTest < ActiveSupport::TestCase
  WINDOW = ProgramWindow.load({ starts_at: "2026-09-25 17:00", ends_at: "2026-10-12 09:00" })

  def et(text) = ActiveSupport::TimeZone[ProgramWindow::ZONE].parse(text)

  setup do
    ProgramWindow.current = WINDOW
    @real_services = ENV["REAL_SERVICES"]
    ENV["REAL_SERVICES"] = "1"
    @tokens = tokens = []
    @refusals = refusals = {}
    @during = during = []
    HttpJson.singleton_class.alias_method(:real_get, :get)
    HttpJson.define_singleton_method(:get) do |url, headers: {}, **|
      token = headers["Authorization"].to_s.delete_prefix("Bearer ")
      tokens << token if url.include?("/spans")
      during.each(&:call)
      failure = refusals[token]
      raise failure if failure.is_a?(Exception)
      raise HttpJson::Error.new("GET #{URI(url).path} -> #{failure}", status: failure) if failure
      url.include?("/spans") ? { "spans" => [] } : { "data" => { "total_seconds" => 0, "projects" => [], "user_id" => 1 } }
    end
  end

  teardown do
    HttpJson.singleton_class.alias_method(:get, :real_get)
    ENV["REAL_SERVICES"] = @real_services
  end

  def participant(token, synced_at: nil)
    user = User.create!(hca_id: "ident!job-#{token}", hackatime_access_token: token)
    user.projects.create!(name: "pet", hackatime_projects: [ "pet-#{token}" ])
    user.update_columns(coding_hours_synced_at: synced_at)
    user
  end

  # A second Postgres session, as another process running the job would have.
  def other_session
    session = ActiveRecord::ConnectionAdapters::PostgreSQLAdapter.new(ActiveRecord::Base.connection_db_config.configuration_hash)
    yield session
  ensure
    session&.disconnect!
  end

  test "one participant's failure does not stop the others" do
    users = %w[hka_a hka_down hka_hangs hka_revoked hka_b].map { participant(it) }
    @refusals.merge!("hka_down" => 500, "hka_hangs" => Net::ReadTimeout.new, "hka_revoked" => 401)
    User.create!(hca_id: "ident!job-unlinked") # no Hackatime, not asked

    travel_to(et("2026-09-28 10:00")) { CodingHoursJob.perform_now }
    assert_equal %w[hka_a hka_down hka_hangs hka_revoked hka_b], @tokens
    synced = users.map { it.reload.coding_hours_synced_at.present? }
    assert_equal [ true, false, false, false, true ], synced
  end

  test "the least recently synced go first, never-synced before all" do
    participant("hka_hour_ago", synced_at: et("2026-09-28 09:00"))
    participant("hka_new")
    participant("hka_day_ago", synced_at: et("2026-09-27 10:00"))
    travel_to(et("2026-09-28 10:00")) { CodingHoursJob.perform_now }
    assert_equal %w[hka_new hka_day_ago hka_hour_ago], @tokens
  end

  test "a run does nothing while another holds the lock, and holds it while it runs" do
    participant("hka_a")
    other_session do |other|
      assert other.select_value("SELECT pg_try_advisory_lock(#{CodingHoursJob::LOCK})")
      travel_to(et("2026-09-28 10:00")) { CodingHoursJob.perform_now }
      assert_empty @tokens, "the other run holds the lock"
      other.select_value("SELECT pg_advisory_unlock(#{CodingHoursJob::LOCK})")

      taken = []
      @during << -> { taken << other.select_value("SELECT pg_try_advisory_lock(#{CodingHoursJob::LOCK})") }
      travel_to(et("2026-09-28 10:00")) { CodingHoursJob.perform_now }
      assert_equal [ "hka_a" ], @tokens
      assert_equal [ false ], taken.uniq, "a second run could not start"
      @during.clear
      assert other.select_value("SELECT pg_try_advisory_lock(#{CodingHoursJob::LOCK})"), "released after the run"
    end
  end

  test "after the window closes, each participant is synced once more, then the job goes quiet" do
    participant("hka_before", synced_at: et("2026-10-12 08:00"))
    participant("hka_after", synced_at: et("2026-10-12 10:00"))
    participant("hka_never")
    travel_to(et("2026-10-12 12:00")) { CodingHoursJob.perform_now }
    assert_equal %w[hka_never hka_before], @tokens
    travel_to(et("2026-10-12 13:00")) { CodingHoursJob.perform_now }
    assert_equal %w[hka_never hka_before], @tokens, "nothing more to ask"
  end

  test "nothing is asked before the program starts" do
    participant("hka_early")
    travel_to(et("2026-09-25 16:00")) { CodingHoursJob.perform_now }
    assert_empty @tokens
  end

  test "Solid Queue runs it at the top of every hour in production" do
    options = Rails.application.config_for(:recurring, env: "production").fetch(:coding_hours)
    task = SolidQueue::RecurringTask.from_configuration(:coding_hours, **options)
    assert task.valid?, task.errors.full_messages.to_sentence
    assert_equal et("2026-09-28 11:00"), task.next_time_after(et("2026-09-28 10:00"))
  end
end
