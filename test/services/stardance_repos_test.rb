require "test_helper"

# The playground mission's repo URLs, with Stardance's rows canned. Nothing
# reaches the network.
class StardanceReposTest < ActiveSupport::TestCase
  FakeMcp = Struct.new(:rows, :asked) do
    def query(sql, question:)
      self.asked = [ sql, question ]
      StardanceMcp::Result.new(columns: %w[repo], rows:)
    end
  end

  def hex(text) = text.unpack1("H*")

  test "fetch: one query, the URLs decoded" do
    mcp = FakeMcp.new([ [ hex("https://github.com/a/b") ], [ hex("https://example.org/ü") ] ])
    assert_equal [ "https://github.com/a/b", "https://example.org/ü" ], StardanceRepos.fetch(mcp)
    sql = mcp.asked.first
    assert_includes sql, "m.slug = 'playground'"
    assert_includes sql, "pma.deleted_at IS NULL AND pma.detached_at IS NULL"
    assert_includes sql, "p.deleted_at IS NULL"
    assert_includes sql, "postable_type = 'Post::ShipEvent'"
    assert_includes sql, "se.certification_status IS DISTINCT FROM 'rejected'"
  end

  test "fetch without a token raises, so callers fail closed" do
    original = StardanceMcp.method(:token)
    StardanceMcp.define_singleton_method(:token) { nil }
    assert_raises(StardanceMcp::Error) { OfflineStardance::REAL.call }
  ensure
    StardanceMcp.define_singleton_method(:token, &original)
  end

  test "status: shipped, clear, or unknown when Stardance can't be read" do
    OfflineStardance.urls = [ "https://github.com/Ziv/Desktop-Pet.git" ]
    assert_equal :shipped, StardanceRepos.status("https://www.github.com/ziv/desktop-pet/tree/main#")
    assert_equal :clear, StardanceRepos.status("https://github.com/ziv/other")
    assert_equal :clear, StardanceRepos.status(nil)
    OfflineStardance.error = StardanceMcp::Error.new("down")
    assert_equal :unknown, StardanceRepos.status("https://github.com/ziv/desktop-pet")
  end

  test "for_project: a project with a ship in the Unified DB is never blocked" do
    OfflineStardance.urls = [ "https://github.com/a/b" ]
    user = User.create!(hca_id: "ident!sr-#{SecureRandom.hex(3)}")
    project = user.projects.create!(name: "pet", code_url: "https://github.com/a/b")
    assert_equal :shipped, StardanceRepos.for_project(project, project.code_url)
    project.ships.create!(user:, claimed_seconds: 60, in_unified: true)
    assert_equal :clear, StardanceRepos.for_project(project, project.code_url)
  end

  test "a ship's code URL and a Stardance repo URL match once normalized" do
    key = UnifiedSearch.normalize("https://github.com/zivzancoeli-commits/Desktop-pet")
    [ "https://github.com/zivzancoeli-commits/desktop-pet/tree/main#",
      "http://www.GitHub.com/zivzancoeli-commits/desktop-pet.git",
      "https://github.com/zivzancoeli-commits/desktop-pet/",
      "github.com/zivzancoeli-commits/desktop-pet?tab=readme" ].each do |url|
      assert_equal key, UnifiedSearch.normalize(url), url
    end
    assert_not_equal key, UnifiedSearch.normalize("https://github.com/zivzancoeli-commits/desktop-pets")
  end
end
