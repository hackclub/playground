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

  # Prizes can be claimed for 7 days after the window ends. Counted in Eastern
  # days, so the close is the same wall-clock hour across a daylight saving change.
  def redeem_ends_at = ends_at.in_time_zone(ZONE) + 7.days
  def redeem_closed?(now = Time.current) = now >= redeem_ends_at
  def redeem_closed_on = redeem_ends_at.strftime("%B %-d")

  # From the end on, no new ship. A pet whose latest ship needs changes can
  # still be shipped again until the same close as claiming prizes.
  def ended?(now = Time.current) = now >= ends_at
  def resubmit?(project) = project.latest_ship&.changes_needed? || false
  def ship_closed_for?(project, now = Time.current)
    ended?(now) && (redeem_closed?(now) || !resubmit?(project))
  end

  # A short line for a pet's ship button once the window has ended, or nil.
  def ship_note(project, now = Time.current)
    return unless ended?(now)
    if !ship_closed_for?(project, now) then "resubmit by #{redeem_ends_at.strftime("%b %-d")}"
    else "shipping closed #{(resubmit?(project) ? redeem_ends_at : ends_at.in_time_zone(ZONE)).strftime("%b %-d")}"
    end
  end
end
