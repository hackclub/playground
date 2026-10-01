require "test_helper"

class ApplicationHelperTest < ActionView::TestCase
  StageHours = Struct.new(:approved_seconds, :pending_seconds, :unshipped_seconds) do
    def scale_seconds = Goal.all.last.seconds
  end

  def layers(approved, pending, unshipped)
    @rendered = meter(StageHours.new(*[ approved, pending, unshipped ].map { (it * Goal.all.last.seconds).round }))
    css_select(".meter-bar > .seg").map { [ it["class"], it["style"] ] }
  end

  # The goals marked reached, and the label read out for the meter, at these
  # approved and pending hours.
  def reached(approved, pending = 0)
    @rendered = meter(StageHours.new((approved * 3600).round, (pending * 3600).round, 0))
    [ css_select(".goal-mark.reached .goal-name").map(&:text), css_select(".meter").first["aria-label"] ]
  end

  test "each stage is a layer from the bar's left end to where it ends, the later stages first" do
    assert_equal [ [ "seg unshipped", "--end: 60.0%" ], [ "seg pending", "--end: 30.0%" ], [ "seg approved", "--end: 10.0%" ] ],
                 layers(0.1, 0.2, 0.3)
  end

  test "a stage with no hours has no layer, and one that reaches the bar's end is full" do
    assert_equal [ [ "seg unshipped", "--end: 70.0%" ], [ "seg approved", "--end: 40.0%" ] ], layers(0.4, 0, 0.3)
    assert_equal [ [ "seg pending full", "--end: 100.0%" ] ], layers(0, 1.2, 0.3)
    assert_equal [ [ "seg pending full", "--end: 100.0%" ], [ "seg approved", "--end: 60.0%" ] ], layers(0.6, 0.5, 0)
    assert_equal [], layers(0, 0, 0)
  end

  test "a goal is reached once approved hours are at or past it, and the meter's label names it" do
    stickers, keychain = Goal.find("stickers"), Goal.find("keychain")
    below = stickers.hours - 1 / 60.0
    assert_equal [ [], "1h 59m approved, 0m pending, 0m unshipped" ], reached(below)
    assert_equal [ [ "stickers" ], "2h 0m approved, 0m pending, 0m unshipped. Reached: 2h stickers" ], reached(stickers.hours)
    assert_equal [ [ "stickers" ], "2h 30m approved, 0m pending, 0m unshipped. Reached: 2h stickers" ], reached(stickers.hours + 0.5)
    assert_equal [ %w[stickers keychain], "5h 0m approved, 0m pending, 0m unshipped. Reached: 2h stickers and 5h keychain" ],
                 reached(keychain.hours)
    assert_equal [], reached(below, 8).first, "pending hours reach nothing"
  end

  test "each goal's mark on the meter is labelled with its hours" do
    user = User.create!(hca_id: "ident!meter-labels")
    @rendered = meter(user.hours)

    assert_select ".goal-mark", count: Goal.all.size
    Goal.all.each do |goal|
      assert_select ".goal-mark", text: "#{goal.hours}h #{goal.key}" do
        assert_select ".goal-hours", text: "#{goal.hours}h"
        assert_select ".goal-name", text: goal.key
      end
    end
  end
end
