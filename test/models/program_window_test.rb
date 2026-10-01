require "test_helper"
require "open3"

# The program window: its times, where they come from, and what stops boot.
class ProgramWindowTest < ActiveSupport::TestCase
  KEYS = %w[PROGRAM_STARTS_AT PROGRAM_ENDS_AT].freeze

  setup { @env = ENV.to_h.slice(*KEYS) }
  teardown { KEYS.each { ENV[it] = @env[it] } }

  def load_with(env)
    KEYS.each { ENV.delete(it) }
    env.each { |k, v| ENV[k] = v }
    ProgramWindow.load
  end

  test "defaults to 5pm US Eastern on the 25th of September to 9am on the 12th of October 2026" do
    window = load_with({})
    assert_equal Time.utc(2026, 9, 25, 21), window.starts_at, "5pm EDT is 21:00 UTC"
    assert_equal Time.utc(2026, 10, 12, 13), window.ends_at, "9am EDT is 13:00 UTC"
    assert_equal "America/New_York", window.starts_at.time_zone.tzinfo.name
    assert_not window.started?(Time.utc(2026, 9, 25, 20, 59, 59))
    assert window.started?(Time.utc(2026, 9, 25, 21))
  end

  test "the environment moves either end, read in US Eastern time with daylight saving" do
    window = load_with("PROGRAM_STARTS_AT" => "2026-10-01 09:30", "PROGRAM_ENDS_AT" => "2026-11-06 17:00")
    assert_equal Time.utc(2026, 10, 1, 13, 30), window.starts_at, "EDT, UTC-4"
    assert_equal Time.utc(2026, 11, 6, 22), window.ends_at, "EST after the clocks go back, UTC-5"
    assert_equal Time.utc(2026, 10, 12, 13), load_with("PROGRAM_STARTS_AT" => "2026-10-01 09:30").ends_at
  end

  test "a value that isn't an Eastern time says which variable and what it got" do
    { "PROGRAM_STARTS_AT" => [ "tomorrow", "2026-09-25", "2026-09-25T17:00:00-04:00", "2026-09-25 5pm", "2026-9-25 17:00",
                               "2026-02-30 17:00", "2026-09-25 24:00", "2026-09-25 17:60", "", "2027-03-14 02:30" ],
      "PROGRAM_ENDS_AT" => [ "soon", "2026-13-01 17:00" ] }.each do |name, values|
      values.each do |value|
        error = assert_raises(ProgramWindow::Invalid, "#{name}=#{value.inspect}") { load_with(name => value) }
        assert_equal "#{name} must be a US Eastern time like 2026-09-25 17:00, not #{value.inspect}", error.message
      end
    end
  end

  test "the end must come after the start" do
    [ "2026-09-25 17:00", "2026-09-25 16:59" ].each do |ends|
      error = assert_raises(ProgramWindow::Invalid) { load_with("PROGRAM_STARTS_AT" => "2026-09-25 17:00", "PROGRAM_ENDS_AT" => ends) }
      assert_equal "PROGRAM_ENDS_AT (#{ends}) is not after PROGRAM_STARTS_AT (2026-09-25 17:00)", error.message
    end
    assert_equal 1.minute, load_with("PROGRAM_STARTS_AT" => "2026-09-25 17:00", "PROGRAM_ENDS_AT" => "2026-09-25 17:01").then { it.ends_at - it.starts_at }
  end

  test "a bad value stops the app from booting" do
    env = { "PROGRAM_STARTS_AT" => "2026-10-10 17:00", "PROGRAM_ENDS_AT" => "2026-10-09 17:00" }
    out, status = Open3.capture2e(env, RbConfig.ruby, "bin/rails", "runner", "puts :booted", chdir: Rails.root.to_s)
    assert_not status.success?
    assert_match "PROGRAM_ENDS_AT (2026-10-09 17:00) is not after PROGRAM_STARTS_AT (2026-10-10 17:00)", out
    assert_no_match "booted", out
  end
end
