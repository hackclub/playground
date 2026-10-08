# Who on Stardance's playground mission was active on a US Eastern day,
# counted the way a participant here is (ProgramStats::ACTIVE_CODING_SECONDS
# of Hackatime time that day), but only on the Hackatime projects linked to
# their projects on that mission. Stardance's database (StardanceMcp) names
# the people, by Slack ID, and their projects. Hackatime's public stats give
# each one's time, one request per person per day.
#
# Someone active here that day already counts in the chart, so they are left
# out here, matched by Slack ID. That match happens here, so no Slack ID from
# this site goes to Stardance.
class StardanceActivity
  # A person on the mission. handle is their Stardance display name, which
  # is also their profile's address, stardance.hackclub.com/@handle.
  Person = Data.define(:slack_id, :handle, :projects)
  # The day's counts, and the active people with their seconds, as
  # [[Person, seconds]], most time first.
  Count = Data.define(:active, :unknown, :people)

  # Every Hackatime project linked to a project on the playground mission,
  # with the Slack ID and Stardance display name of the person who linked
  # it. Text goes hex-encoded, as the MCP's text table can't carry a pipe or
  # a newline.
  SQL = <<~SQL.squish.freeze
    SELECT DISTINCT u.slack_id, encode(convert_to(u.display_name, 'UTF8'), 'hex') AS handle,
      encode(convert_to(uhp.name, 'UTF8'), 'hex') AS project
    FROM stardance.project_mission_attachments pma
    JOIN stardance.projects p ON p.id = pma.project_id AND p.deleted_at IS NULL
    JOIN stardance.user_hackatime_projects uhp ON uhp.project_id = pma.project_id
    JOIN stardance.users u ON u.id = uhp.user_id
    JOIN stardance.missions m ON m.id = pma.mission_id
    WHERE m.slug = 'playground' AND pma.deleted_at IS NULL AND pma.detached_at IS NULL
      AND u.slack_id IS NOT NULL AND u.slack_id <> '' AND uhp.name IS NOT NULL AND uhp.name <> ''
    ORDER BY 1, 3
  SQL
  QUESTION = "Which Slack IDs, display names and Hackatime projects belong to the playground mission's projects, " \
             "to list playground's daily active users by Hackatime time?".freeze

  # Each person once, with every one of their projects.
  def self.people(mcp = StardanceMcp.new)
    mcp.query(SQL, question: QUESTION).rows.group_by(&:first).map do |slack_id, rows|
      Person.new(slack_id:, handle: decode(rows.first[1]).presence, projects: rows.map { decode(it[2]) })
    end
  end

  def self.decode(hex) = [ hex.to_s ].pack("H*").force_encoding(Encoding::UTF_8)

  # The Slack IDs of the participants here who were active on each Eastern
  # day of the window, by ProgramStats' rule: { Date => Set }.
  def self.active_here(window = ProgramWindow.current)
    coded = CodingHour.where(user: User.where(admin: false)).per_day_and_user(window, at_least: ProgramStats::ACTIVE_CODING_SECONDS)
    slack_ids = User.where(id: coded.values.flatten(1).map(&:first).uniq).where.not(slack_id: [ nil, "" ]).pluck(:id, :slack_id).to_h
    coded.transform_values { |rows| rows.filter_map { |id, _| slack_ids[id] }.to_set }
  end

  # Who of the people was active on the day, and how many Hackatime would
  # not show. One person's failure counts them as unknown and is logged; the
  # others go on.
  def self.count(day, people, here: Set.new)
    zone = ActiveSupport::TimeZone[ProgramWindow::ZONE]
    from = zone.local(day.year, day.month, day.day)
    to = from.tomorrow
    seconds = people.reject { here.include?(it.slack_id) }.to_h do |person|
      [ person, Hackatime.public_seconds(person.slack_id, person.projects, from:, to:) ]
    rescue => e
      # The message names the person's Slack ID in Hackatime's URL, so only
      # the kind of failure is logged.
      Rails.logger.error("Stardance Hackatime lookup failed for #{day}: #{e.class} #{e.try(:status)}".strip)
      [ person, nil ]
    end
    active = seconds.select { |_, s| s && s >= ProgramStats::ACTIVE_CODING_SECONDS }.sort_by { |person, s| [ -s, person.slack_id ] }
    Count.new(active: active.size, unknown: seconds.values.count(nil), people: active)
  end
end
