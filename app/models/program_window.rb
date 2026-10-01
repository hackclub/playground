# The program window. Only Hackatime time inside it counts, and the Hackatime
# picker lists only projects with time inside it. It runs from starts_at up
# to, not including, ends_at. PROGRAM_STARTS_AT and PROGRAM_ENDS_AT set both
# as "YYYY-MM-DD HH:MM" in US Eastern time (config/program.yml).
class ProgramWindow < Data.define(:starts_at, :ends_at)
  ZONE = "America/New_York"
  FORMAT = "%Y-%m-%d %H:%M"
  class Invalid < ArgumentError; end

  class << self
    # Tests set their own window through ProgramWindow.current=.
    attr_writer :current
    def current = @current ||= load
  end

  # Checked at boot, so a bad value stops the app instead of miscounting.
  def self.load(config = Rails.application.config_for(:program))
    starts_at = time(config[:starts_at], "PROGRAM_STARTS_AT")
    ends_at = time(config[:ends_at], "PROGRAM_ENDS_AT")
    raise Invalid, "PROGRAM_ENDS_AT (#{config[:ends_at]}) is not after PROGRAM_STARTS_AT (#{config[:starts_at]})" unless ends_at > starts_at
    new(starts_at:, ends_at:)
  end

  # Reading the time back refuses what parsing would roll over: 2026-02-30,
  # 24:00, and a time the clocks skip when daylight saving starts.
  def self.time(value, name)
    text = value.to_s
    at = begin
      ActiveSupport::TimeZone[ZONE].strptime(text, FORMAT) if text.match?(/\A\d{4}-\d{2}-\d{2} \d{2}:\d{2}\z/)
    rescue ArgumentError
    end
    return at if at&.strftime(FORMAT) == text
    raise Invalid, "#{name} must be a US Eastern time like 2026-09-25 17:00, not #{text.inspect}"
  end
  private_class_method :time

  def started?(now = Time.current) = now >= starts_at
end
