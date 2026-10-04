# Marks the participants due the "no time yet" email: signed up at least WAIT
# ago, with no ship and no coding time on any pet. The mark reaches Loops as
# "Loops - playgroundNoTimeNudge", and a Loops workflow sends the email when
# it appears. A text value, not a timestamp, so the mark does not count as
# activity. A participant is marked once, and the mark stays. Nobody is marked
# outside the program window, so the emails stop with the program.
#
# NO_TIME_NUDGE=1 turns marking on. Without it a run only logs how many are
# due. Emails in NO_TIME_NUDGE_TEST_EMAILS (comma separated) skip the wait and
# are marked even while marking is off, to test the email end to end.
class NoTimeNudge
  WAIT = 72.hours
  # A participant with Hackatime linked counts only after a coding hours sync
  # this recent, so time they logged since the last one is seen first.
  FRESH = 2.hours
  VALUE = "yes".freeze

  def self.enabled? = ENV["NO_TIME_NUDGE"] == "1"
  def self.test_emails = ENV["NO_TIME_NUDGE_TEST_EMAILS"].to_s.downcase.split(",").map(&:strip).compact_blank

  # Unmarked participants with no ship, no time, and a fresh view of their time.
  def self.idle(now = Time.current)
    User.where(no_time_nudge_at: nil, banned_at: nil)
        .where.missing(:ships)
        .where.not(id: CodingHour.select(:user_id))
        .where.not(id: Project.where("tracked_seconds > 0").select(:user_id))
        .where("users.hackatime_access_token IS NULL OR users.coding_hours_synced_at >= ?", now - FRESH)
  end

  # Those idle for WAIT since signup, and the test emails without the wait.
  def self.due(now = Time.current)
    idle(now).where(created_at: ..(now - WAIT))
             .or(idle(now).where("LOWER(users.email) IN (?)", test_emails.presence || [ "" ]))
  end

  # Marks who is due and puts their rows next in the Airtable sync. Returns
  # how many were marked.
  def self.run(now: Time.current, window: ProgramWindow.current)
    return 0 unless window.started?(now) && now < window.ends_at
    due = due(now).pluck(:id, :email)
    marked = enabled? ? due : due.select { |_, email| test_emails.include?(email.to_s.downcase) }
    User.where(id: marked.map(&:first)).update_all(no_time_nudge_at: now, synced_at: nil)
    Rails.logger.info("no-time nudge: #{due.size} due, #{marked.size} marked#{" (dry run)" unless enabled?}")
    marked.size
  end
end
