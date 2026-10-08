require "test_helper"

# Counting Stardance's playground people for a day, with Stardance's rows and
# Hackatime's answers canned. Hackatime.public_seconds is swapped for the
# test; nothing reaches the network.
class StardanceActivityTest < ActiveSupport::TestCase
  DAY = Date.new(2026, 10, 1)

  # Stands in for StardanceMcp, answering one table.
  FakeMcp = Struct.new(:rows, :asked) do
    def query(sql, question:)
      self.asked = [ sql, question ]
      StardanceMcp::Result.new(columns: %w[slack_id handle project], rows:)
    end
  end

  setup do
    @asked = asked = []
    @seconds = seconds = {}
    Hackatime.singleton_class.alias_method(:real_public_seconds, :public_seconds)
    Hackatime.define_singleton_method(:public_seconds) do |slack_id, names, from:, to:|
      asked << [ slack_id, names, from, to ]
      answer = seconds[slack_id]
      answer.is_a?(Exception) ? raise(answer) : answer
    end
  end

  teardown { Hackatime.singleton_class.alias_method(:public_seconds, :real_public_seconds) }

  def person(slack_id, *projects) = StardanceActivity::Person.new(slack_id:, handle: "h-#{slack_id}", projects:)

  test "people: each Slack ID once, with its Stardance name and Hackatime projects, all decoded" do
    mcp = FakeMcp.new([ [ "U0A", "4e6f7661", "6f72626974" ], [ "U0A", "4e6f7661", "6f726269742d617274" ], [ "U0B", "", "c3a9746f696c65207c2032" ] ])
    assert_equal [ StardanceActivity::Person.new(slack_id: "U0A", handle: "Nova", projects: %w[orbit orbit-art]),
                   StardanceActivity::Person.new(slack_id: "U0B", handle: nil, projects: [ "étoile | 2" ]) ], StardanceActivity.people(mcp)
    sql, question = mcp.asked
    assert_match "m.slug = 'playground'", sql
    assert_match "encode(convert_to(uhp.name, 'UTF8'), 'hex')", sql
    assert_match "encode(convert_to(u.display_name, 'UTF8'), 'hex')", sql
    assert question.present?
  end

  test "count: a minute or more on the day is active, private stats unknown, a failure unknown, and anyone active here is not asked" do
    people = [ person("U0A", "orbit"), person("U0B", "star"), person("U0C", "comet"), person("U0D", "moon"), person("U0E", "sun"), person("U0HERE", "pet") ]
    @seconds.merge!("U0A" => 60, "U0B" => 59, "U0C" => nil, "U0D" => Net::ReadTimeout.new, "U0E" => 3600)
    count = StardanceActivity.count(DAY, people, here: Set["U0HERE"])
    assert_equal [ 2, 2 ], [ count.active, count.unknown ]
    # The active ones, most time first.
    assert_equal [ [ "U0E", 3600 ], [ "U0A", 60 ] ], count.people.map { |p, seconds| [ p.slack_id, seconds ] }
    assert_equal %w[U0A U0B U0C U0D U0E], @asked.map(&:first)
    _, names, from, to = @asked.first
    assert_equal [ "orbit" ], names
    assert_equal [ "2026-10-01T00:00:00-04:00", "2026-10-02T00:00:00-04:00" ], [ from.iso8601, to.iso8601 ]
  end

  test "count: the day a clock change makes 25 hours long is asked whole" do
    StardanceActivity.count(Date.new(2026, 11, 1), [ person("U0A", "orbit") ])
    _, _, from, to = @asked.first
    assert_equal 25.hours, to - from
  end

  test "active_here: the Slack IDs of participants with a minute or more each Eastern day, admins and the unlinked left out" do
    ProgramWindow.current = ProgramWindow.load({ starts_at: "2026-09-28 09:00", ends_at: "2026-10-10 09:00" })
    coder = User.create!(hca_id: "ident!sd-coder", slack_id: "U0HERE")
    brief = User.create!(hca_id: "ident!sd-brief", slack_id: "U0BRIEF")
    admin = User.create!(hca_id: "ident!sd-admin", slack_id: "U0ADMIN", admin: true)
    unlinked = User.create!(hca_id: "ident!sd-unlinked")
    # 1pm Eastern on October 1 is 5pm UTC.
    hour = Time.utc(2026, 10, 1, 17)
    [ [ coder, 30 ], [ brief, 59 ], [ admin, 600 ], [ unlinked, 600 ] ].each { |user, seconds| CodingHour.create!(user:, hour:, seconds:) }
    CodingHour.create!(user: coder, hour: hour + 1.hour, seconds: 30)
    assert_equal({ DAY => Set["U0HERE"] }, StardanceActivity.active_here)
  end
end
