require "test_helper"

# A browser's journey through a guide, as counts: each row is the browsers
# that started on its day, from its sources, and reached at least its stage
# and its minutes. A report from one point to the next adds one to each
# count the browser newly belongs to, and nothing ever goes down.
class GuideJourneyDayTest < ActiveSupport::TestCase
  DAY = Date.new(2026, 10, 8)
  CLUBS = GuideSections.find("clubs")
  P = GuideJourneyDay::Point
  T = TrafficSource::Touch
  FROM = { first: T.new(source: "clubs", medium: "email", campaign: "launch"), last: T.new(source: "slack", medium: "referral", campaign: "") }.freeze

  test "a first report counts the browser in each stage and bucket up to where it is" do
    assert_equal [ [ "opened", 0 ] ], cells(nil, [ "opened", 0 ])
    assert_equal [ [ "opened", 0 ], [ "opened", 2 ], [ "setup-godot", 0 ], [ "setup-godot", 2 ] ], cells(nil, [ "setup-godot", 2 ])
  end

  test "a report from one point to the next counts only what is new, and one that goes back or names nothing counts nothing" do
    assert_equal [ [ "opened", 2 ], [ "setup-godot", 2 ], [ "github", 0 ], [ "github", 2 ] ], cells([ "setup-godot", 0 ], [ "github", 2 ])
    assert_equal [], cells([ "github", 2 ], [ "github", 2 ])
    assert_nil cells([ "github", 2 ], [ "setup-godot", 5 ]), "a stage back"
    assert_nil cells([ "github", 5 ], [ "sync", 2 ]), "a bucket back"
    assert_nil cells(nil, [ "hackatime", 0 ]), "the clubs' guide has no Hackatime"
    assert_nil cells(nil, [ "opened", 3 ]), "no such bucket"
    assert_nil cells([ "nowhere", 0 ], [ "github", 0 ])
  end

  test "a browser that moves on stays one reader in every count, with its sources, and no count goes down" do
    report(nil, [ "opened", 0 ])
    report([ "opened", 0 ], [ "setup-godot", 2 ])
    before = GuideJourneyDay.pluck(:stage, :minutes, :readers).to_h { [ it.first(2), it.last ] }
    report([ "setup-godot", 2 ], [ "github", 5 ])
    after = GuideJourneyDay.pluck(:stage, :minutes, :readers).to_h { [ it.first(2), it.last ] }
    assert before.all? { |cell, readers| after.fetch(cell) >= readers }
    assert_equal [ 1 ], after.values.uniq
    assert_equal 9, after.size, "3 stages by 3 buckets"
    assert_equal [ [ DAY, "clubs", "clubs", "email", "launch", "slack", "referral", "" ] ],
                 GuideJourneyDay.distinct.pluck(:day, :guide, :first_source, :first_medium, :first_campaign, :last_source, :last_medium, :last_campaign)
  end

  test "two browsers at once both count, and a count below zero cannot be stored" do
    2.times { report(nil, [ "setup-godot", 0 ]) }
    assert_equal [ 2 ], GuideJourneyDay.distinct.pluck(:readers)
    assert_raises(ActiveRecord::CheckViolation) { GuideJourneyDay.transaction(requires_new: true) { GuideJourneyDay.update_all(readers: -1) } }
    assert_raises(ActiveRecord::CheckViolation) { GuideJourneyDay.transaction(requires_new: true) { GuideJourneyDay.update_all(minutes: 3) } }
    assert_equal [ 2 ], GuideJourneyDay.distinct.pluck(:readers)
  end

  test "it holds counts and sources, and nothing that names a person or a browser" do
    assert_equal %w[day first_campaign first_medium first_source guide id last_campaign last_medium last_source minutes readers stage],
                 GuideJourneyDay.column_names.sort
  end

  private

  def cells(from, to) = GuideJourneyDay.cells(CLUBS, from: from && P.new(*from), to: P.new(*to))&.map(&:deconstruct)
  def report(from, to) = GuideJourneyDay.count!(guide: CLUBS, day: DAY, **FROM, from: from && P.new(*from), to: P.new(*to))
end
