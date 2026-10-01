require "test_helper"

# The code may live anywhere public. A GitHub repository also needs a README
# and gets its commits counted. Code anywhere else skips both, for a reviewer
# to read by hand.
class SubmitGateCodeTest < ActiveSupport::TestCase
  setup do
    @user = User.create!(hca_id: "ident!gate-#{SecureRandom.hex(3)}", verification_status: "verified", ysws_eligible: true)
    # GitHub would answer that the repository has no README and one commit.
    OfflineGithub.repo = OfflineGithub::REPO.with(readme: false, commits: 1)
  end

  def gate(code_url) = SubmitGate.new(@user.projects.create!(name: "rock", code_url:))
  def result(gate, key) = gate.checks.find { it.key == key }.ok

  test "code on GitLab or Codeberg passes, and skips the README and the commits" do
    %w[https://gitlab.com/pet/rock https://codeberg.org/pet/rock].each do |url|
      gate = gate(url)
      assert result(gate, :repo), url
      assert result(gate, :readme), "#{url} needs no README check"
      assert result(gate, :commits), "#{url} has no commits warning"
      assert_nil gate.repo, "GitHub is not asked about #{url}"
    end
  end

  test "a GitHub repository keeps all three checks" do
    gate = gate("https://github.com/pet/rock")
    assert result(gate, :repo)
    assert_not result(gate, :readme)
    assert_not result(gate, :commits)
    assert_equal [ :commits ], gate.warnings.map(&:key)

    OfflineGithub.repo = OfflineGithub::REPO.with(private: true)
    assert_not result(gate("https://github.com/pet/rock"), :repo), "a private repository fails"
    assert_not result(gate("https://github.com/pet"), :repo), "a GitHub link that is not a repository fails"
  end

  test "code at a link that doesn't load fails" do
    OfflineGithub.unreachable << "https://gitlab.com/pet/gone"
    gate = gate("https://gitlab.com/pet/gone")
    assert_not result(gate, :repo)
    assert_equal "your pet needs a link to its code", gate.checks.find { it.key == :repo }.label
    assert_not result(gate(nil), :repo), "no link fails too"
  end

  test "the labels speak to the participant about their pet" do
    labels = gate(nil).checks.map(&:label)
    assert_empty labels.grep(/the pet/)
    assert_includes labels, "your pet needs a name"
    assert_includes labels, "your pet needs new hours to ship"
  end

  test "a shipped link off itch.io warns, and does not stop the ship" do
    host = ->(url) { SubmitGate.new(@user.projects.create!(name: "rock", playable_url: url)).checks.find { it.key == :playable_host } }
    %w[https://itch.io/games https://pet.itch.io/rock https://Pet.Itch.io/rock].each { assert host.call(it).ok, it }
    assert host.call(nil).ok, "no link is the shipped link check's to ask for"
    %w[https://github.com/pet/rock/releases/latest https://pet.example.com https://notitch.io/rock https://itch.io.example.com/x].each do |url|
      check = host.call(url)
      assert_not check.ok, url
      assert_not check.blocker?, "#{url} only warns"
      assert_equal "the shipped link needs to go to a page where someone can experience your pet", check.label
    end
    assert_not SubmitGate.new(@user.projects.create!(name: "rock", playable_url: "https://pet.example.com")).blockers.map(&:key).include?(:playable_host)
  end
end
