# Turns a project's unshipped hours into a ship. Re-checks eligibility with
# Hack Club Auth and the gate on fresh data first.
class Shipper
  class Blocked < StandardError; end

  def self.ship!(project)
    user = project.user
    HackClubAuth.for(user).refresh_user! if user.hca_access_token.present? || FakeServices.on?
    stats = Hackatime.for(user).stats(project.hackatime_projects)
    project.update_columns(tracked_seconds: stats.total_seconds, tracked_at: Time.current)
    user.update_columns(hackatime_trust_level: stats.trust_level, hackatime_user_id: stats.user_id.presence || user.hackatime_user_id)

    gate = SubmitGate.new(project.reload)
    raise Blocked, gate.blockers.map(&:label).to_sentence unless gate.passed?

    lapses = LapseLinks.for(user, project.hackatime_projects)
    # A reship claims only new time, so only Lapses no earlier ship recorded.
    seen = project.ships.reject(&:changes_needed?).flat_map { Array(it.snapshot["lapses"]).map { |l| l["id"] } }
    lapses = lapses.with(lapses: lapses.lapses.reject { seen.include?(it.id) })
    warnings = gate.warnings.map(&:label)
    art = project.unshipped_seconds.positive? ? lapses.seconds.to_f / project.unshipped_seconds : 0
    warnings << "Lapse time is #{(art * 100).round}% of the claimed hours; art counts at most #{Ship::ART_CAP_PERCENT}%" if art > Ship::ART_CAP_PERCENT / 100.0
    warnings << "Lapses unavailable: #{lapses.error}" if lapses.error

    # Two ship requests at once both pass the gate, so the lock lets one in.
    project.with_lock do
      raise Blocked, "your last ship needs its review first" if project.ships.reload.any?(&:pending?)
      create_ship!(project, user, stats, gate, lapses, warnings).tap do
        # The link belongs to this ship. The next ship needs a message of its own.
        project.update_columns(ship_message_url: nil)
      end
    end
  rescue Hackatime::Unlinked
    # The pet page asks Hackatime again, so its checklist shows the same.
    project.update_columns(tracked_at: nil)
    raise Blocked, "#{Hackatime::UNLINKED} link it again below"
  end

  def self.create_ship!(project, user, stats, gate, lapses, warnings)
    project.ships.create!(
      user: user,
      claimed_seconds: project.unshipped_seconds,
      snapshot: {
        "hackatime_user_id" => user.hackatime_user_id,
        "trust_level" => stats.trust_level,
        "hackatime_projects" => project.hackatime_projects,
        "projects" => stats.projects,
        "tracked_seconds" => stats.total_seconds,
        "window" => { "starts_at" => ProgramWindow.current.starts_at.iso8601, "ends_at" => ProgramWindow.current.ends_at.iso8601 },
        "previously_claimed_seconds" => project.claimed_by,
        "commits" => gate.repo&.commits,
        "release" => gate.release&.to_h,
        "warnings" => warnings,
        "code_url" => project.code_url, "playable_url" => project.playable_url,
        "ship_message_url" => project.ship_message_url,
        # The cover stays in screenshot_url for code that reads one.
        "screenshot_url" => project.screenshot_url, "screenshots" => project.screenshot_urls,
        "description" => project.description,
        "taken_at" => Time.current.iso8601
      }.merge(lapses.to_h)
    )
  end
end
