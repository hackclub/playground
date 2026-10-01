require "application_system_test_case"

# The meter as drawn: pending hatching from its tile, and each stage's end
# drawn as a marker edge by a mask.
class MeterHatchingTest < ApplicationSystemTestCase
  test "the hatching loads and each stage's end is drawn" do
    user = log_in_as "participant"
    admin = User.create!(hca_id: "ident!meter-admin", admin: true)
    project = user.projects.create!(name: "meter pet", tracked_seconds: 4 * 3600, tracked_at: Time.current)
    project.ships.create!(user:, claimed_seconds: 3600).tap do |ship|
      ship.approve_review!(by: admin, seconds: 3600, judgement: "ok", feedback: nil)
      ship.pass_fraud!(by: admin)
    end
    project.ships.create!(user:, claimed_seconds: 2 * 3600)
    visit root_path(open: "goal")

    within_frame(find(".ship-frame")) do
      assert_selector ".meter-bar .seg", count: 3
      drawn = page.evaluate_async_script(<<~JS)
        const done = arguments[arguments.length - 1]
        const ends = [...document.querySelectorAll(".meter-bar .seg")].map(seg => {
          const style = getComputedStyle(seg)
          return [seg.className, (style.maskImage || style.webkitMaskImage).includes("data:image/svg+xml")]
        })
        const tile = getComputedStyle(document.querySelector(".seg.pending")).backgroundImage.match(/url\\("(.+)"\\)/)[1]
        fetch(tile).then(response => done({ ends, tile: response.ok && response.headers.get("content-type") }))
      JS
      assert_equal [ [ "seg unshipped", true ], [ "seg pending", true ], [ "seg approved", true ] ], drawn["ends"]
      assert_equal "image/svg+xml", drawn["tile"]
    end
  end
end
