require "test_helper"

# The playground mission's hours by stage, with Stardance's rows canned.
# Nothing reaches the network.
class StardanceStagesTest < ActiveSupport::TestCase
  H = 3600
  COLUMNS = %w[project repo tracked status shipped paid].freeze

  FakeMcp = Struct.new(:rows, :asked) do
    def query(sql, question:)
      self.asked = [ sql, question ]
      StardanceMcp::Result.new(columns: COLUMNS, rows:)
    end
  end

  def hex(text) = text.unpack1("H*")
  def ship(status, shipped, paid = shipped) = StardanceStages::ShipRow.new(status:, shipped:, paid:)
  def entry(tracked, *ships, repo: "") = StardanceStages::Entry.new(repo:, tracked:, ships:)

  test "fetch: one query, a project with its ships oldest first, and a project with none" do
    mcp = FakeMcp.new([
      [ "7", hex("https://github.com/a/orbit"), "36000", "approved", "7200", "3600" ],
      [ "7", hex("https://github.com/a/orbit"), "36000", "pending", "10800", "10800" ],
      [ "9", "", "1800", "", "0", "0" ]
    ])
    assert_equal [ entry(36000, ship("approved", 7200, 3600), ship("pending", 10800), repo: "https://github.com/a/orbit"), entry(1800) ],
                 StardanceStages.fetch(mcp)
    sql, question = mcp.asked
    assert_includes sql, "m.slug = 'playground'"
    assert_includes sql, "pma.deleted_at IS NULL AND pma.detached_at IS NULL"
    assert_includes sql, "p.deleted_at IS NULL"
    assert_includes sql, "encode(convert_to(coalesce(mission.repo_url, ''), 'UTF8'), 'hex')"
    assert_includes sql, "LEFT JOIN stardance.post_ship_events"
    assert question.present?
  end

  test "a ship's stage: approved at its paid hours, pending and misfiled in review, returned back to unshipped, rejected in none" do
    project = entry(30 * H, ship("approved", 6 * H, 4 * H), ship("rejected", 5 * H), ship("misfiled", H), ship("returned", 2 * H), ship("pending", 3 * H))
    assert_equal [ 4 * H, 4 * H, 15 * H ], [ project.approved, project.pending, project.unshipped ]
    # The last ship is pending, so nothing waits on changes.
    assert_equal 0, project.returned
  end

  test "a project whose last ship was sent back holds those hours as unshipped and returned" do
    project = entry(10 * H, ship("approved", 3 * H), ship("returned", 4 * H))
    assert_equal [ 3 * H, 0, 7 * H, 4 * H ], [ project.approved, project.pending, project.unshipped, project.returned ]
  end

  test "unshipped never goes below nothing, and returned never above unshipped" do
    assert_equal 0, entry(H, ship("pending", 2 * H)).unshipped
    assert_equal H, entry(H, ship("returned", 2 * H)).returned
  end

  test "sum: the stages over every project, leaving out one whose repo is a pet here" do
    projects = [ entry(10 * H, ship("approved", 4 * H), repo: "https://GitHub.com/a/orbit.git"),
                 entry(5 * H, ship("pending", 2 * H), repo: "https://github.com/b/comet"),
                 entry(H, ship("returned", H)),
                 entry(0) ]
    totals = StardanceStages.sum(projects, here: Set.new([ UnifiedSearch.normalize("https://github.com/a/orbit") ]))
    assert_equal({ approved: 0, pending: 2 * H, unshipped: 4 * H, returned: H, projects: 3, left_out_projects: 1, left_out_seconds: 10 * H },
                 totals.to_h)
    assert_equal 6 * H, StardanceStages.sum(projects).pending + StardanceStages.sum(projects).approved
  end

  test "here: the code links of pets counted in this site's stages, and of their ships" do
    ann = User.create!(hca_id: "ident!sd-ann", email: "ann@example.com", display_name: "ann", display_name_source: "generated")
    admin = User.create!(hca_id: "ident!sd-mod", email: "mod@example.com", display_name: "mod", display_name_source: "generated", admin: true)
    tracked = ann.projects.create!(name: "tracked", hackatime_projects: [ "t" ], tracked_seconds: H, code_url: "https://github.com/ann/tracked")
    ann.projects.create!(name: "idle", hackatime_projects: [ "i" ], tracked_seconds: 0, code_url: "https://github.com/ann/idle")
    shipped = ann.projects.create!(name: "shipped", hackatime_projects: [ "s" ], tracked_seconds: 2 * H, code_url: "https://github.com/ann/renamed")
    shipped.ships.create!(user: ann, claimed_seconds: 2 * H, snapshot: { "code_url" => "https://github.com/ann/shipped" })
    admin.projects.create!(name: "mods", hackatime_projects: [ "m" ], tracked_seconds: H, code_url: "https://github.com/mod/mods")
    assert tracked.ships.none?
    assert_equal %w[github.com/ann/renamed github.com/ann/shipped github.com/ann/tracked].to_set, StardanceStages.here
  end
end
