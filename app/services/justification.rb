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
    projects_list +
      (", #{window_note}" if window_note).to_s +
      (snap["previously_claimed_seconds"].to_i.positive? ? "; earlier ships claimed #{Hours.format(snap["previously_claimed_seconds"])}, this ship claims the time since" : "")
  end

  def deflation
    s = @ship
    parts = []
    parts << deflation_sentence if deflated?
    parts << "Fraud check deducted #{Hours.format(s.fraud_deduction_seconds)}: #{s.fraud_notes}" if s.fraud_deduction_seconds.positive?
    parts.join(" ").presence
  end

  def to_s
    s = @ship
    snap = s.snapshot
    lines = []
    lines << "Hackatime projects: #{projects_list}#{", #{window_note}" if window_note}."
    lines << combined_total_line if snap["tracked_seconds"]
    lines << "Submitter Hackatime ID: #{snap["hackatime_user_id"]}. Trust level at ship: #{snap["trust_level"]}."
    if snap["previously_claimed_seconds"].to_i.positive?
      lines << "Update: #{Hours.format(snap["previously_claimed_seconds"])} were claimed by earlier ships; this ship claims only the time since."
    end
    lines << "Claimed: #{Hours.format(s.claimed_seconds)}. Approved by review: #{Hours.format(s.review_seconds)}" +
             (deflated? ? "." : ", no deflation.")
    lines << deflation_sentence if deflated?
    lapses = Array(snap["lapses"])
    if lapses.any?
      lines << "Lapse links: " + lapses.map { "#{it["url"]} (#{it["title"]}, #{Hours.format(it["duration"])})" }.join(", ") + "."
    end
    lines << ""
    lines << "Specific technical features: #{s.review_judgement}"
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

  # Under a minute is form rounding, not a deflation. Older ships stored it.
  def deflated? = @ship.deflated_seconds >= 60

  def deflation_sentence
    s = @ship
    "Deflated from #{Hours.format(s.claimed_seconds)} to #{Hours.format(s.review_seconds)}" +
      (s.review_deflation_reason.present? ? " because #{s.review_deflation_reason.strip.chomp(".")}." : ".")
  end

  # One entry per project, "name M/D/YYYY-M/D/YYYY (Xh Ym)", as the guide asks:
  # https://docs.hackclub.com/handbook/quality-and-integrity/override-hours-spent-justification
  # The snapshot keeps one window for the ship, so every project shares it.
  def projects_list
    range = us_date_range
    @ship.snapshot.fetch("projects", {}).reject { |name, _| Hackatime.ignored?(name) }
         .map { |name, sec| [ name, range, "(#{Hours.format(sec)})" ].compact.join(" ") }.join(", ")
  end

  # Hackatime's combined total can differ from the sum of the per-project
  # totals, so the text says so rather than leave a spot-checker to wonder.
  def combined_total_line
    "Hackatime total for these projects together: #{Hours.format(@ship.snapshot["tracked_seconds"])} (this can differ from the sum of the per-project totals)."
  end

  def window_times
    snap = @ship.snapshot
    window = snap["window"] or return nil
    starts, ends, taken = [ window["starts_at"], window["ends_at"], snap["taken_at"] ].map { Time.zone.parse(it.to_s) }
    [ starts, [ ends, taken ].compact.min ].map { it.in_time_zone(ProgramWindow::ZONE) }
  end

  def us_date_range
    from, to = window_times
    return nil unless from
    "#{from.strftime("%-m/%-d/%Y")}-#{to.strftime("%-m/%-d/%Y")}"
  end

  # The exact window, once, after the list. Ships taken before the window
  # existed counted all time.
  def window_note
    snap = @ship.snapshot
    from, to = window_times
    return "all time up to #{snap["taken_at"]&.first(10)}" unless from
    "window #{from.strftime(ProgramWindow::FORMAT)} to #{to.strftime(ProgramWindow::FORMAT)} US Eastern time"
  end
end
