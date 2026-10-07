# The text for Airtable's "Override Hours Spent Justification". Code writes
# the numbers; the reviewer writes only the judgement (horizons does the same).
# Fields follow
# https://docs.hackclub.com/handbook/quality-and-integrity/override-hours-spent-justification
class Justification
  def initialize(ship)
    @ship = ship
  end

  # The parts the component's "Justification - ..." fields take. Its
  # "Automation - Unified Justification" formula joins them.
  def hackatime_projects
    snap = @ship.snapshot
    snap.fetch("projects", {}).reject { |name, _| Hackatime.ignored?(name) }.map { |name, sec| "#{name} (#{Hours.format(sec)})" }.join(", ") +
      ", #{date_range}" +
      (snap["previously_claimed_seconds"].to_i.positive? ? "; earlier ships claimed #{Hours.format(snap["previously_claimed_seconds"])}, this ship claims the time since" : "")
  end

  def deflation
    s = @ship
    parts = []
    parts << "Review deflated #{Hours.format(s.deflated_seconds)} of #{Hours.format(s.claimed_seconds)} claimed." if s.deflated_seconds.positive?
    parts << "Fraud check deducted #{Hours.format(s.fraud_deduction_seconds)}: #{s.fraud_notes}" if s.fraud_deduction_seconds.positive?
    parts.join(" ").presence
  end

  def to_s
    s = @ship
    snap = s.snapshot
    lines = []
    lines << "Hackatime projects: " + snap.fetch("projects", {}).reject { |name, _| Hackatime.ignored?(name) }.map { |name, sec| "#{name} (#{Hours.format(sec)})" }.join(", ") +
             ", #{date_range}."
    lines << "Submitter Hackatime ID: #{snap["hackatime_user_id"]}. Trust level at ship: #{snap["trust_level"]}."
    if snap["previously_claimed_seconds"].to_i.positive?
      lines << "Update: #{Hours.format(snap["previously_claimed_seconds"])} were claimed by earlier ships; this ship claims only the time since."
    end
    lines << "Claimed: #{Hours.format(s.claimed_seconds)}. Approved by review: #{Hours.format(s.review_seconds)}" +
             (s.deflated_seconds.positive? ? ", deflated by #{Hours.format(s.deflated_seconds)}." : ", no deflation.")
    lines << ""
    lines << "Reviewer judgement: #{s.review_judgement}"
    lines << ""
    if s.fraud_deduction_seconds.positive?
      lines << "Fraud check deducted #{Hours.format(s.fraud_deduction_seconds)}: #{s.fraud_notes}"
    end
    lines << "Final approved hours: #{Hours.format(s.approved_seconds)}." if s.approved_seconds
    lines << "Reviewed by #{s.reviewer&.display_name} on #{s.reviewed_at&.to_date}. Fraud check by #{s.fraud_reviewer&.display_name} on #{s.fraud_reviewed_at&.to_date}."
    if s.review_checklist["art_cap"]
      lines << "Art hours count at most #{Ship::ART_CAP_PERCENT}% of approved hours; the reviewer checked the Lapse time against that cap."
    end
    lines.join("\n")
  end

  private

  # From the window's start to the ship, or to the window's end if that came
  # first. Ships taken before the window existed counted all time.
  def date_range
    snap = @ship.snapshot
    window = snap["window"] or return "all time up to #{snap["taken_at"]&.first(10)}"
    starts, ends, taken = [ window["starts_at"], window["ends_at"], snap["taken_at"] ].map { Time.zone.parse(it.to_s) }
    from, to = [ starts, [ ends, taken ].compact.min ].map { it.in_time_zone(ProgramWindow::ZONE).strftime(ProgramWindow::FORMAT) }
    "#{from} to #{to} US Eastern time"
  end
end
