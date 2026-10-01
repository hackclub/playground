require "test_helper"

# ship.exe's list: only the checks that fail, the two description checks under
# one field, a tip on a step that could be unclear, and a step fixed while the
# popup is open kept in the list, ticked.
class ShipChecklistItemsTest < ActiveSupport::TestCase
  READY = { description: "a rock that walks along your taskbar", code_url: "https://github.com/pet/rock",
            ship_message_url: "https://hackclub.slack.com/archives/C0C51NCK1DG/p1759012345678901", playable_url: "https://pet.itch.io/rock", hackatime_projects: [ "rock-pet" ],
            screenshots: [ { "id" => "shot", "key" => "shot.webp", "url" => "https://playground.hackclub-assets.com/shot.webp" } ],
            tracked_seconds: 3600 }.freeze

  setup do
    @user = User.create!(hca_id: "ident!list-#{SecureRandom.hex(3)}", verification_status: "verified",
                         ysws_eligible: true, hackatime_access_token: "fake")
  end

  test "a bare pet lists each blocker once, with the field that fixes it" do
    checklist = ShipChecklist.new(@user.projects.create!(name: "rock"))
    items = checklist.items
    assert_equal %w[description hackatime_projects code_url playable_url screenshot ship_message_url], items.map(&:key)
    assert_equal %i[description hackatime_projects code_url playable_url screenshot ship_message_url], items.map(&:field)
    assert items.none?(&:ok)
    assert items.all?(&:blocker)
    # The label says what to do. Only the shipped link and the ship message have more to say.
    assert_equal [ nil, nil, ShipChecklist::TIPS[:repo], ShipChecklist::TIPS[:playable], nil, ShipChecklist::TIPS[:ship_message] ], items.map(&:tip)
  end

  test "a step that needs another waits off the list until that one passes, and the ship still waits for it" do
    OfflineGithub.repo = OfflineGithub::REPO.with(private: true, readme: false, commits: 1)
    project = @user.projects.create!(READY.merge(name: "rock", hackatime_projects: [], tracked_seconds: 0))
    checklist = ShipChecklist.new(project, shown: %w[readme new_hours commits])
    assert_equal %w[hackatime_projects code_url], checklist.items.map(&:key)
    assert_includes checklist.gate.blockers.map(&:key), :readme
    assert_includes checklist.gate.blockers.map(&:key), :new_hours
    assert_not checklist.passed?

    OfflineGithub.repo = OfflineGithub::REPO.with(readme: false, commits: 1)
    project.update!(hackatime_projects: [ "rock-pet" ])
    items = ShipChecklist.new(project).items
    assert_equal %w[new_hours readme commits], items.map(&:key)
    assert_equal [ "the repository needs a README", nil ], items.find { it.key == "readme" }.to_h.values_at(:label, :tip)
    assert_match "Hackatime or Lapse since your last ship", items.find { it.key == "new_hours" }.tip
    assert_equal [ "commits" ], items.reject(&:blocker).map(&:key)
  end

  test "the description step keeps one name, empty, short, or done" do
    project = @user.projects.create!(READY.merge(name: "rock", description: nil))
    labels = [ nil, "a small rock", "a rock that walks along your taskbar" ].map do |description|
      project.update!(description:)
      ShipChecklist.new(project, shown: %w[description]).items.find { it.key == "description" }.label
    end
    assert_equal [ "the description needs at least 20 characters" ], labels.uniq
  end

  test "a short description is the description step, and its label is all it says" do
    item = ShipChecklist.new(@user.projects.create!(READY.merge(name: "rock", description: "a small rock"))).items.sole
    assert_equal "description", item.key
    assert_equal :description, item.field
    assert_equal "the description needs at least 20 characters", item.label
    assert_nil item.tip
  end

  test "a check that could not run says so in its tip" do
    Github.singleton_class.alias_method(:offline_repo, :repo)
    Github.define_singleton_method(:repo) { |_name| raise HttpJson::Error.new("GET api.github.com -> 503", status: 503) }
    item = ShipChecklist.new(@user.projects.create!(READY.merge(name: "rock"))).items.find { it.key == "code_url" }
    assert_equal [ "your pet needs a link to its code", ShipChecklist::UNCHECKED_TIP ], [ item.label, item.tip ]
  ensure
    Github.singleton_class.alias_method(:repo, :offline_repo)
  end

  test "a step fixed while the popup is open stays, ticked, with its field, and the next opening leaves it out" do
    project = @user.projects.create!(READY.merge(name: "rock"))
    assert_empty ShipChecklist.new(project).items
    assert ShipChecklist.new(project).passed?

    items = ShipChecklist.new(project, shown: %w[description code_url]).items
    assert_equal %w[description code_url], items.map(&:key)
    assert items.all?(&:ok)
    assert_equal [ :description, :code_url ], items.map(&:field)
  end

  test "a warning is listed as a warning and does not stop the ship" do
    OfflineGithub.repo = OfflineGithub::REPO.with(commits: 1)
    checklist = ShipChecklist.new(@user.projects.create!(READY.merge(name: "rock")))
    assert_equal [ [ "commits", false ] ], checklist.items.map { [ it.key, it.blocker ] }
    assert checklist.passed?
  end

  test "a shipped link off itch.io is listed as a warning with a tip and no field, and the pet can still ship" do
    project = @user.projects.create!(READY.merge(name: "rock", playable_url: "https://pet.example.com"))
    checklist = ShipChecklist.new(project)
    item = checklist.items.sole
    assert_equal [ "playable_host", false, nil ], [ item.key, item.blocker, item.field ]
    assert_equal ShipChecklist::TIPS[:playable_host], item.tip
    assert checklist.passed?, "a warning does not stop the ship"
  end
end
