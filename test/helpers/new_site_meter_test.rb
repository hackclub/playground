require "test_helper"

# The meter beside the guide, as text: the total shows once, on its tag, and
# each prize says only its hours and what it waits on.
class NewSiteMeterTest < ActionView::TestCase
  helper NewSiteHelper
  include NewSiteHelper

  # Hours in each stage, without projects or ships behind them.
  class StageHours < Hours
    attr_reader :approved_seconds, :pending_seconds, :unshipped_seconds

    def initialize(approved: 0, pending: 0, unshipped: 0)
      @approved_seconds, @pending_seconds, @unshipped_seconds = approved, pending, unshipped
    end
  end

  Hub = Struct.new(:hours, :redemptions)
  Viewer = Struct.new(:eligible?, :banned?)
  def current_user = @viewer
  helper_method :current_user

  setup { @viewer = Viewer.new(true, false) }

  # Renders the meter on its own: each render replaces the last one.
  def render_meter(hours, redemptions: {})
    @hub = Hub.new(hours, redemptions)
    self.rendered = +""
    render partial: "guides/vertical_meter"
  end

  test "the tag shows the total once, and each prize only its hours, at each edge" do
    { 0 => [ "0m", 0 ], 12 => [ "12m", 0 ], 119 => [ "1h 59m", 0 ], 120 => [ "2h", 1 ], 121 => [ "2h 1m", 1 ],
      299 => [ "4h 59m", 1 ], 300 => [ "5h", 2 ], 599 => [ "9h 59m", 2 ], 600 => [ "10h", 3 ], 840 => [ "14h", 3 ] }.each do |minutes, (total, reached)|
      render_meter(StageHours.new(approved: minutes * 60))
      assert_select ".vmeter-now-tag[tabindex='0']", { count: 1, text: total }, "at #{minutes}m"
      assert_select ".vmeter-now[style='--now: #{(minutes / 600.0).clamp(0, 1).round(4)}']", 1
      assert_equal %w[2h 5h 10h], css_select(".vmeter-goals .goal-hours").map(&:text)
      assert_no_match %r{\d/\d}, css_select(".vmeter-goals").first.text, "no prize repeats the total"
      assert_select ".vmeter-goals li.reached", reached
      assert_select ".vmeter-goals li.reached .visually-hidden", { count: reached, text: "reached," }
      assert_select ".vmeter-tick.reached", reached
    end
  end

  test "minutes round down, so the tag never shows a goal's hours early, and past the top it shows whole hours" do
    assert_equal "0m", meter_total(StageHours.new)
    assert_equal "1h 59m", meter_total(StageHours.new(approved: 2.hours - 1))
    assert_equal "9h 59m", meter_total(StageHours.new(approved: 10.hours - 1))
    assert_equal "10h", meter_total(StageHours.new(approved: 10.hours + 59.minutes))
    assert_equal "14h", meter_total(StageHours.new(approved: 14.hours + 59.minutes))
  end

  test "the tag counts every stage and says how it splits, while only approved hours reach a prize" do
    render_meter(StageHours.new(approved: 2.hours, pending: 3.hours, unshipped: 5.hours + 15.minutes))
    assert_select ".vmeter-now-tag", text: "10h" do |tags|
      assert_equal "2h approved\n3h pending\n5h 15m unshipped", tags.first["data-tip"]
      assert_equal "10h 15m so far, 2h approved, 3h pending, 5h 15m unshipped", tags.first["aria-label"]
    end
    assert_select ".vmeter-goals li.reached", 1
    assert_select ".vmeter-goals li", text: /2h\s+· redeem/
    assert_select ".vmeter-goals li", text: /5h\s+· in review/
    assert_select ".vmeter-goals li", text: /10h\s+· ship to redeem/
    assert_select ".vseg[data-tip='unshipped · 5h 15m']", 1
  end

  test "with no hours the tag says so on hover" do
    render_meter(StageHours.new)
    assert_select ".vmeter-now-tag[data-tip='no hours yet'][aria-label='0m so far']", 1
    assert_select ".vseg", 0
  end

  test "a reached prize keeps its redemption and eligibility words" do
    hours = StageHours.new(approved: 2.hours)
    render_meter(hours, redemptions: { "stickers" => Struct.new(:status).new("fulfilled") })
    assert_select ".vmeter-goals li.reached", text: /2h\s+· shipped to you!/
    render_meter(hours, redemptions: { "stickers" => Struct.new(:status).new("pending") })
    assert_select ".vmeter-goals li.reached", text: /2h\s+· redeemed · pending/
    @viewer = Viewer.new(false, false)
    render_meter(hours)
    assert_select ".vmeter-goals li.reached", text: /2h\s+· verify to redeem/
    assert_select ".vmeter-goals a", 0
  end
end
