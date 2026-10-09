# The repos of the projects shipped on Stardance, read from Stardance's
# database (StardanceMcp). A project counts when it is on the playground
# mission and has a ship event that is not rejected. Stardance takes such a
# project, so playground does not submit it, review it, or send it to the
# Unified DB. A repo only attached to the mission, with no ship, does not
# count. The first into the Unified DB wins: a project with a ship already in
# the Unified DB is never blocked. URLs go hex-encoded, as the MCP's text
# table can't carry a pipe or a newline.
#
# certification_status on 2026-10-08: approved, returned, pending, misfiled,
# rejected. Only rejected is not a ship.
module StardanceRepos
  SQL = <<~SQL.squish.freeze
    SELECT DISTINCT encode(convert_to(p.repo_url, 'UTF8'), 'hex') AS repo
    FROM stardance.project_mission_attachments pma
    JOIN stardance.projects p ON p.id = pma.project_id AND p.deleted_at IS NULL
    JOIN stardance.missions m ON m.id = pma.mission_id
    JOIN stardance.posts po ON po.project_id = p.id AND po.postable_type = 'Post::ShipEvent'
    JOIN stardance.post_ship_events se ON se.id = po.postable_id
    WHERE m.slug = 'playground' AND pma.deleted_at IS NULL AND pma.detached_at IS NULL
      AND p.repo_url IS NOT NULL AND p.repo_url <> ''
      AND se.certification_status IS DISTINCT FROM 'rejected'
    ORDER BY 1
  SQL
  QUESTION = "Which repo URLs belong to playground mission projects that have a ship on Stardance, " \
             "so playground does not take a project that Stardance reviews?".freeze
  CACHE_KEY = "stardance-shipped-repos".freeze
  CACHE_FOR = 5.minutes
  # What a participant or a reviewer is told.
  MESSAGE = "This project is shipped on Stardance, so it's reviewed there.".freeze

  module_function

  # One query. Raises when the token is missing or the server fails.
  def fetch(mcp = nil)
    raise StardanceMcp::Error, "no Stardance MCP token" if mcp.nil? && !StardanceMcp.configured?
    (mcp || StardanceMcp.new).query(SQL, question: QUESTION).rows.map { [ it.first ].pack("H*").force_encoding(Encoding::UTF_8) }
  end

  # The normalized repo URLs, kept for a few minutes so a page load does not
  # ask the MCP. A failed read raises and is not kept.
  def keys
    Rails.cache.fetch(CACHE_KEY, expires_in: CACHE_FOR) { fetch.map { UnifiedSearch.normalize(it) }.reject(&:blank?).uniq }
  end

  # True or false, and raises when Stardance can't be read.
  def shipped?(code_url, keys = self.keys)
    key = UnifiedSearch.normalize(code_url)
    key.present? && keys.include?(key)
  end

  # :shipped, :clear, or :unknown when Stardance can't be read. A caller that
  # must not block a person on an outage treats :unknown as :clear.
  def status(code_url)
    shipped?(code_url) ? :shipped : :clear
  rescue => e
    Rails.logger.error("Stardance shipped repos not read (#{e.class})")
    :unknown
  end

  # The status for a project's ship. Once a ship of the project is in the
  # Unified DB the project stays with playground, so Stardance is not asked.
  def for_project(project, code_url)
    project.ships.exists?(in_unified: true) ? :clear : status(code_url)
  end
end
