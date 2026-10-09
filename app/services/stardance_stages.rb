# The hours of Stardance's playground mission, in the meter's three stages,
# read from Stardance's database (StardanceMcp).
#
# A Stardance project's time is the Hackatime time its devlogs logged
# (projects.duration_seconds, the sum of its devlogs' time). Each ship
# records the hours logged since the ship before it (hours_at_ship), and an
# approved ship the hours it paid out on (hours_at_payout, set at payout).
# By the ship's certification_status, as this site's ships count:
#
#   approved  approved, its paid hours, or its shipped hours until it pays
#   pending   pending, misfiled, or any status not named here: still with
#             Stardance's reviewers
#   returned  sent back for changes, so its hours are unshipped again
#   rejected  in no stage, as a rejected ship's hours here are cut
#
# Unshipped is the project's time less what its ships claimed, returned
# ships aside.
#
# A project whose repo is also a pet here, counted in this site's stages,
# is left out, so no hour counts twice. Repos match as StardanceRepos
# matches them, by UnifiedSearch.normalize. Only totals are kept.
module StardanceStages
  # A row a ship, or a project with no ship, its status empty. Text goes
  # hex-encoded, as the MCP's text table can't carry a pipe or a newline.
  SQL = <<~SQL.squish.freeze
    WITH mission AS (
      SELECT DISTINCT p.id, p.repo_url, p.duration_seconds
      FROM stardance.project_mission_attachments pma
      JOIN stardance.projects p ON p.id = pma.project_id AND p.deleted_at IS NULL
      JOIN stardance.missions m ON m.id = pma.mission_id
      WHERE m.slug = 'playground' AND pma.deleted_at IS NULL AND pma.detached_at IS NULL)
    SELECT mission.id AS project, encode(convert_to(coalesce(mission.repo_url, ''), 'UTF8'), 'hex') AS repo,
      coalesce(mission.duration_seconds, 0) AS tracked, coalesce(se.certification_status, '') AS status,
      round(coalesce(se.hours_at_ship, 0) * 3600)::bigint AS shipped,
      round(coalesce(se.hours_at_payout, se.hours_at_ship, 0) * 3600)::bigint AS paid
    FROM mission
    LEFT JOIN stardance.posts po ON po.project_id = mission.id AND po.postable_type = 'Post::ShipEvent'
    LEFT JOIN stardance.post_ship_events se ON se.id = po.postable_id
    ORDER BY mission.id, se.created_at NULLS FIRST
  SQL
  QUESTION = "How many hours do the playground mission's projects hold, and how many of them are shipped, " \
             "in review, or approved, for the hours pie on playground's admin stats page?".freeze

  ShipRow = Data.define(:status, :shipped, :paid)
  Entry = Data.define(:repo, :tracked, :ships) do
    def approved = ships.select { it.status == "approved" }.sum(&:paid)
    def pending = ships.reject { %w[approved returned rejected].include?(it.status) }.sum(&:shipped)
    def unshipped = [ tracked - ships.reject { it.status == "returned" }.sum(&:shipped), 0 ].max
    # Unshipped hours of a project whose latest ship was sent back: the
    # changes it waits on. Part of unshipped, not beside it.
    def returned = ships.last&.status == "returned" ? [ ships.last.shipped, unshipped ].min : 0
    def total = approved + pending + unshipped
  end
  # Seconds in each stage, the projects counted, and the projects and
  # seconds left out as pets here.
  Totals = Data.define(:approved, :pending, :unshipped, :returned, :projects, :left_out_projects, :left_out_seconds)

  module_function

  # Each project on the mission with its ships, oldest ship first.
  def fetch(mcp = StardanceMcp.new)
    rows = mcp.query(SQL, question: QUESTION).hashes
    rows.group_by { it["project"] }.map do |_, ships|
      first = ships.first
      Entry.new(repo: [ first["repo"] ].pack("H*").force_encoding(Encoding::UTF_8), tracked: first["tracked"].to_i,
                ships: ships.reject { it["status"].blank? }.map { ShipRow.new(status: it["status"], shipped: it["shipped"].to_i, paid: it["paid"].to_i) })
    end
  end

  # The stages summed, leaving out each project whose repo is in here,
  # normalized repo URLs.
  def sum(projects, here: Set.new)
    left_out, counted = projects.partition { (key = UnifiedSearch.normalize(it.repo)).present? && here.include?(key) }
    Totals.new(approved: counted.sum(&:approved), pending: counted.sum(&:pending), unshipped: counted.sum(&:unshipped),
               returned: counted.sum(&:returned), projects: counted.size,
               left_out_projects: left_out.size, left_out_seconds: left_out.sum(&:total))
  end

  # The normalized repo URLs of the pets that count in this site's stages:
  # a participant's pet with unshipped hours, or with a ship pending or
  # approved. A pet's code link and those its ships were taken with all
  # count, as a link can change after a ship.
  def here
    pets = ::Project.where(user: User.where(admin: false)).includes(:ships).to_a.select { counted_here?(it) }
    snapshots = ::Ship.where(project_id: pets.map(&:id)).pluck(Arel.sql("snapshot->>'code_url'"))
    (pets.map(&:code_url) + snapshots).filter_map { UnifiedSearch.normalize(it).presence }.to_set
  end

  def counted_here?(pet)
    ships = pet.ships.to_a
    pet.unshipped_seconds(ships).positive? || ships.any? { it.pending? || (it.approved? && it.approved_seconds.to_i.positive?) }
  end
end
