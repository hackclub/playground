require "test_helper"

# The hours pie: this site's stages, then Stardance's in their own fills.
class StatsHelperTest < ActionView::TestCase
  include StatsHelper

  H = 3600

  def hours(seconds) = Hours.format(seconds)

  # The stages' wedges, bottom layer first. The bottom one reaches all the
  # way round, so it is a whole circle.
  def wedges = css_select("svg.pie path, svg.pie circle:not(.outline)").map { it["class"] }

  test "this site's stages alone: a wedge a stage, and only the blue hatching" do
    render plain: hours_pie({ approved: 2 * H, pending: H, unshipped: H })
    assert_equal %w[unshipped pending approved], wedges
    assert_select "svg.pie pattern", 1
    assert_select "svg.pie pattern#pie-pending image[href*='meter/pending']"
    assert_select "svg.pie[aria-label=?]", "approved 2h 0m, 50%; pending 1h 0m, 25%; unshipped 1h 0m, 25%"
  end

  test "Stardance's stages follow this site's, each in its own fill, and an empty stage draws nothing" do
    render plain: hours_pie({ approved: 2 * H, pending: 0, unshipped: H }, stardance: { approved: H, pending: 3 * H, unshipped: H })
    assert_select "svg.pie pattern#pie-stardance-pending image[href*='meter/pending-stardance']"
    assert_select "svg.pie[aria-label=?]",
                  "approved 2h 0m, 25%; unshipped 1h 0m, 13%; Stardance approved 1h 0m, 13%; Stardance pending 3h 0m, 38%; Stardance unshipped 1h 0m, 13%"
    # Layers are drawn last stage first, so the first stage sits on top.
    assert_equal %w[stardance-unshipped stardance-pending stardance-approved unshipped approved], wedges
  end

  test "Stardance's hours alone fill the pie" do
    render plain: hours_pie({ approved: 0, pending: 0, unshipped: 0 }, stardance: { approved: 0, pending: 0, unshipped: 2 * H })
    assert_equal %w[stardance-unshipped], wedges
  end
end
