require "test_helper"

# Where readers stop in a guide: each section in the guide's order, with
# the browsers that reached it over the days, their share of the first
# section's, the drop from the section before, and the biggest drop marked.
class GuideFunnelTest < ActiveSupport::TestCase
  DAY = Date.new(2026, 10, 7)

  test "each section in guide order, with its share of the first and its drop from the one before, the biggest marked" do
    { "setup-godot" => 10, "hackatime" => 8, "github" => 8, "sync" => 3, "commands" => 4 }.each do |section, readers|
      GuideSectionDay.create!(day: DAY, guide: "desktop", section:, readers:)
    end
    # The day before counts too; a month before, and another guide, do not.
    GuideSectionDay.create!(day: DAY - 1, guide: "desktop", section: "setup-godot", readers: 2)
    GuideSectionDay.create!(day: DAY - 30, guide: "desktop", section: "setup-godot", readers: 50)
    GuideSectionDay.create!(day: DAY, guide: "clubs", section: "setup-godot", readers: 99)

    rows = GuideFunnel.new(GuideSections.find("desktop"), (DAY - 1)..DAY).rows
    assert_equal GuideSections.find("desktop").sections, rows.map(&:section)
    assert_equal [ "Set up Godot", "Install Godot Hackatime", "Make a GitHub Repository" ], rows.first(3).map(&:name)
    assert_equal [ 12, 8, 8, 3, 4, 0 ], rows.first(6).map(&:readers)
    assert_equal [ 1.0, 8 / 12.0, 8 / 12.0, 3 / 12.0, 4 / 12.0, 0.0 ], rows.first(6).map(&:share)
    # A later section can count more than the one before: a link skips ahead.
    assert_equal [ nil, 4, 0, 5, -1, 4 ], rows.first(6).map(&:drop)
    assert_equal [ nil, 4 / 12.0, 0.0, 5 / 8.0 ], rows.first(4).map(&:drop_share)
    assert_equal [ "sync" ], rows.select(&:biggest).map(&:section)
  end

  test "a guide nobody reached in the days is empty, with no shares and no biggest drop" do
    GuideSectionDay.create!(day: DAY, guide: "stardance", section: "movement", readers: 3)
    funnel = GuideFunnel.new(GuideSections.find("clubs"), DAY..DAY)
    assert funnel.empty?
    assert_equal [ nil ], funnel.rows.map(&:share).uniq
    assert_empty funnel.rows.select(&:biggest)

    # With no reader of the first section, there is no share of it.
    funnel = GuideFunnel.new(GuideSections.find("stardance"), DAY..DAY)
    assert_not funnel.empty?
    assert_nil funnel.rows.find { it.section == "movement" }.share
  end
end
