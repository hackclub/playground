# The repos of the projects shipped on Stardance, read from Stardance's
# database (StardanceMcp), each with its Stardance project id. A project
# counts when it is on the playground mission and has a ship event that is
# approved or still waits for Stardance's review. Stardance takes such a
# project, so playground does not submit it, review it, or send it to the
# Unified DB. A repo only attached to the mission, with no ship, does not
# count. A ship Stardance returned for changes or rejected does not count
# either, since Stardance does not treat the project as shipped. The first
# into the Unified DB wins: a project with a ship already in the Unified DB
# is never blocked. Text goes hex-encoded, as the MCP's text table can't
# carry a pipe or a newline. The project id is an integer, so it goes as is.
#
# certification_status on 2026-10-13: approved, pending, returned, rejected,
# misfiled. An empty status waits for review like pending.
module StardanceRepos
  SQL = <<~SQL.squish.freeze
    SELECT DISTINCT encode(convert_to(p.repo_url, 'UTF8'), 'hex') AS repo, p.id AS project_id
    FROM stardance.project_mission_attachments pma
    JOIN stardance.projects p ON p.id = pma.project_id AND p.deleted_at IS NULL
    JOIN stardance.missions m ON m.id = pma.mission_id
    JOIN stardance.posts po ON po.project_id = p.id AND po.postable_type = 'Post::ShipEvent'
    JOIN stardance.post_ship_events se ON se.id = po.postable_id
    WHERE m.slug = 'playground' AND pma.deleted_at IS NULL AND pma.detached_at IS NULL
      AND p.repo_url IS NOT NULL AND p.repo_url <> ''
      AND COALESCE(se.certification_status, 'pending') NOT IN ('returned', 'rejected')
    ORDER BY 1, 2
  SQL
  QUESTION = "Which repo URLs, and which Stardance project ids, belong to playground mission projects that have a ship " \
             "on Stardance that is approved or waits for review, so playground does not take a project that Stardance reviews?".freeze
  # The version is in the key, so a cache written in another shape is not read.
  CACHE_KEY = "stardance-shipped-repos-v2".freeze
  CACHE_FOR = 5.minutes
  # What a participant or a reviewer is told. The links to the Stardance
  # projects follow it (see message).
  MESSAGE = "This project is shipped on Stardance, so it's reviewed there.".freeze
  PROJECT_URL = "https://stardance.hackclub.com/projects/%d".freeze

  # One repo URL of a project shipped on Stardance, and that project's id.
  Repo = Data.define(:url, :id)

  module_function

  # One query. Raises when the token is missing or the server fails.
  def fetch(mcp = nil)
    raise StardanceMcp::Error, "no Stardance MCP token" if mcp.nil? && !StardanceMcp.configured?
    (mcp || StardanceMcp.new).query(SQL, question: QUESTION).rows.map do |hex, id|
      Repo.new([ hex ].pack("H*").force_encoding(Encoding::UTF_8), Integer(id, exception: false))
    end
  end

  # The normalized repo URLs shipped on Stardance, each with the ids of its
  # Stardance projects, kept for a few minutes so a page load does not ask
  # the MCP. A failed read raises and is not kept.
  def index
    Rails.cache.fetch(CACHE_KEY, expires_in: CACHE_FOR) do
      fetch.each_with_object({}) do |repo, found|
        key = UnifiedSearch.normalize(repo.url)
        next if key.blank?
        ids = (found[key] ||= [])
        ids << repo.id if repo.id
      end.transform_values { it.uniq.sort }
    end
  end

  # True or false, and raises when Stardance can't be read.
  def shipped?(code_url, index = self.index)
    key = UnifiedSearch.normalize(code_url)
    key.present? && index.key?(key)
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

  # The Stardance project ids of a repo, none when it is not shipped there
  # or Stardance can't be read.
  def project_ids(code_url)
    key = UnifiedSearch.normalize(code_url)
    key.present? ? Array(index[key]) : []
  rescue => e
    Rails.logger.error("Stardance project ids not read (#{e.class})")
    []
  end

  def project_url(id) = format(PROJECT_URL, id)

  # MESSAGE as text, with the URL of each Stardance project after it.
  def message(ids = [])
    [ MESSAGE, *ids.map { project_url(it) } ].join(" ")
  end
end
