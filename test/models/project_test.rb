require "test_helper"

# A pet's screenshots are an ordered list of saved images, cover first.
class ProjectTest < ActiveSupport::TestCase
  setup { @project = User.create!(hca_id: "ident!shots").projects.create!(name: "rock") }

  def shot(n) = { "id" => "shot-#{n}", "key" => "screenshots/#{n}.webp", "url" => "https://playground.hackclub-assets.com/#{n}.webp" }

  test "the first screenshot is the cover, and a pet with none has no cover" do
    assert_nil @project.screenshot_url
    assert_empty @project.screenshot_urls
    @project.update!(screenshots: [ shot(2), shot(1) ])
    assert_equal "https://playground.hackclub-assets.com/2.webp", @project.screenshot_url
    assert_equal %w[2 1], @project.screenshot_urls.map { it[%r{(\d)\.webp}, 1] }
    assert_equal shot(1), @project.screenshot("shot-1")
    assert_nil @project.screenshot("shot-9")
  end

  test "a pet holds up to the limit, each a saved image with an id and a web link" do
    @project.screenshots = (1..ScreenshotLimits::PER_PET).map { shot(it) }
    assert @project.valid?
    @project.screenshots += [ shot(7) ]
    assert_includes @project.tap(&:validate).errors[:screenshots], "hold at most #{ScreenshotLimits::PER_PET}"

    [ shot(1).except("id"), shot(1).merge("url" => "javascript:alert(1)"), "https://playground.hackclub-assets.com/1.webp" ].each do |bad|
      @project.screenshots = [ bad ]
      assert_includes @project.tap(&:validate).errors[:screenshots], "must each be a saved image", bad.inspect
    end
  end

  test "a Hackatime project name holds no comma, and names clash without regard to case or edge spaces" do
    @project.update!(hackatime_projects: [ "rock-pet" ])
    other = @project.user.projects.new(name: "frog", hackatime_projects: [ "rock-pet,frog-widget" ])
    assert_includes other.tap(&:validate).errors[:hackatime_projects], "must each be one Hackatime project, with no commas"
    other.hackatime_projects = [ " Rock-Pet " ]
    assert other.tap(&:validate).errors[:hackatime_projects].any? { it.start_with?("already linked to another pet") }
  end

  test "a Hackatime project a pet shipped stays with that pet after it is unlinked there" do
    @project.update!(hackatime_projects: [ "rock-pet", "rock-pet-art" ])
    ship = @project.ships.create!(user: @project.user, claimed_seconds: 3600,
                                  snapshot: { "hackatime_projects" => [ "rock-pet" ], "projects" => { "rock-pet-art" => 60 } })
    @project.update!(hackatime_projects: [])
    other = @project.user.projects.new(name: "frog", hackatime_projects: [ "rock-pet" ])
    assert_not other.valid?, "named in the ship"
    other.hackatime_projects = [ "rock-pet-art" ]
    assert_not other.valid?, "counted in an older ship's projects"
    assert @project.reload.update(hackatime_projects: [ "rock-pet" ]), "its own pet links it again"

    ship.update!(state: "changes_needed", review_status: "changes_needed")
    @project.update!(hackatime_projects: [])
    assert other.valid?, "a ship sent back for changes claimed nothing"
  end

  test "a code link with a dot-only part is not a GitHub repository" do
    assert_equal "pet/rock", Project.new(code_url: "https://github.com/pet/rock.git").github_repo
    assert_nil Project.new(code_url: "https://github.com/../rock").github_repo
    assert_nil Project.new(code_url: "https://github.com/pet/..").github_repo
  end
end
