require "test_helper"

# The hourly count of Stardance's playground people, with the MCP and
# Hackatime swapped out: StardanceActivity.people answers canned people, and
# Hackatime.public_seconds a minute for everyone.
class StardanceActivityJobTest < ActiveSupport::TestCase
  WINDOW = ProgramWindow.load({ starts_at: "2026-09-28 09:00", ends_at: "2026-10-03 09:00" })

  def et(text) = ActiveSupport::TimeZone[ProgramWindow::ZONE].parse(text)

  setup do
    ProgramWindow.current = WINDOW
    @asked = asked = []
    @people = people = { "U0A" => [ "orbit" ], "U0HERE" => [ "pet" ] }
    @token = "sd_token"
    @originals = { StardanceMcp => %i[token], StardanceActivity => %i[people], Hackatime => %i[public_seconds] }
                   .flat_map { |target, names| names.map { [ target, it, target.method(it) ] } }
    test = self
    StardanceMcp.define_singleton_method(:token) { test.instance_variable_get(:@token) }
    StardanceActivity.define_singleton_method(:people) do |*|
      raise test.instance_variable_get(:@people_error) if test.instance_variable_get(:@people_error)
      people
    end
    Hackatime.define_singleton_method(:public_seconds) do |slack_id, _names, from:, **|
      asked << [ slack_id, from.to_date ]
      60
    end
  end

  teardown { @originals.each { |target, name, original| target.define_singleton_method(name, &original) } }

  def counted = StardanceActiveDay.order(:day).pluck(:day, :active, :unknown)

  test "without a token it asks nothing and stores nothing" do
    @token = nil
    travel_to(et("2026-09-30 12:00")) { StardanceActivityJob.perform_now }
    assert_empty @asked
    assert_empty counted
  end

  test "the first run counts every day of the window so far, later runs only today and yesterday" do
    travel_to(et("2026-09-30 12:00")) { StardanceActivityJob.perform_now }
    days = [ Date.new(2026, 9, 28), Date.new(2026, 9, 29), Date.new(2026, 9, 30) ]
    assert_equal days.map { [ it, 2, 0 ] }, counted
    assert_equal days.flat_map { |day| %w[U0A U0HERE].map { [ it, day ] } }, @asked

    @asked.clear
    travel_to(et("2026-10-01 12:00")) { StardanceActivityJob.perform_now }
    assert_equal [ Date.new(2026, 9, 30), Date.new(2026, 10, 1) ], @asked.map(&:last).uniq
    assert_equal 4, counted.size
  end

  test "a site participant active that day counts once, as a participant" do
    coder = User.create!(hca_id: "ident!sd-job-coder", slack_id: "U0HERE")
    CodingHour.create!(user: coder, hour: Time.utc(2026, 9, 29, 17), seconds: 600)
    travel_to(et("2026-09-29 20:00")) { StardanceActivityJob.perform_now }
    assert_equal [ [ Date.new(2026, 9, 28), 2, 0 ], [ Date.new(2026, 9, 29), 1, 0 ] ], counted
    assert_not_includes @asked, [ "U0HERE", Date.new(2026, 9, 29) ]
  end

  test "once the window has closed, each day is counted once more and then left alone" do
    travel_to(et("2026-10-03 08:00")) { StardanceActivityJob.perform_now }
    assert_equal 6, counted.size
    @asked.clear
    travel_to(et("2026-10-03 10:00")) { StardanceActivityJob.perform_now }
    assert_equal [ Date.new(2026, 10, 2), Date.new(2026, 10, 3) ], @asked.map(&:last).uniq
    @asked.clear
    travel_to(et("2026-10-03 11:00")) { StardanceActivityJob.perform_now }
    travel_to(et("2026-10-05 11:00")) { StardanceActivityJob.perform_now }
    assert_empty @asked
  end

  test "a rejected token logs one line and stores nothing" do
    @people_error = StardanceMcp::Rejected.new(StardanceMcp::REJECTED, status: 401)
    logged = capture_log { travel_to(et("2026-09-30 12:00")) { StardanceActivityJob.perform_now } }
    assert_equal [ "Stardance MCP token rejected; sign in again" ], logged.lines.map(&:strip).grep(/Stardance/)
    assert_empty counted
  end

  test "before the window opens it asks nothing" do
    travel_to(et("2026-09-27 12:00")) { StardanceActivityJob.perform_now }
    assert_empty @asked
  end

  private

  def capture_log
    io = StringIO.new
    original = Rails.logger
    Rails.logger = ActiveSupport::Logger.new(io)
    yield
    io.string
  ensure
    Rails.logger = original
  end
end
