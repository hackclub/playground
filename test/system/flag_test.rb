require "application_system_test_case"

# The Hack Club 2026 banner at the desktop's top left. The app serves it at
# froppii's 220px flag width, its two pennants link to hackclub.com, and the
# sky beside them, the icons, and the windows keep their own clicks.
class FlagTest < ApplicationSystemTestCase
  # Points on the banner's own 534x207 drawing.
  ON_BANNER = { "the join" => [ 320, 150 ], "the 2026 pennant" => [ 420, 150 ], "the left end" => [ 5, 80 ] }.freeze
  BESIDE_BANNER = { "the sky below HACK" => [ 120, 180 ], "the sky right of 2026" => [ 530, 175 ], "the sky above 2026" => [ 450, 90 ] }.freeze

  test "the banner links to Hack Club, and the desktop around it keeps its clicks" do
    [ [ 1440, 900 ], [ 1024, 768 ], [ 390, 844 ] ].each do |width, height|
      resize_browser_to(width, height) do
        visit root_path
        banner = find("#background-flag")
        assert_equal "Hack Club 2026", banner[:alt]
        assert_match %r{/assets/landing/hack-club-flag-2026-\w+\.svg\z}, banner[:src]
        assert_equal [ 534, 220, 85 ], page.evaluate_async_script(<<~JS, banner), "at #{width}px"
          const [img, done] = arguments
          img.decode().then(() => done([img.naturalWidth, img.width, img.height].map(Math.round)))
        JS
        assert_equal "https://hackclub.com/", find("#flag-link")[:href]

        ON_BANNER.each { |spot, point| assert_equal "flag-link", element_on_banner(point), "#{spot} at #{width}px" }
        BESIDE_BANNER.each { |spot, point| assert_not_equal "flag-link", element_on_banner(point), "#{spot} at #{width}px" }
        assert_empty page.evaluate_script(<<~JS), "no icon under the banner at #{width}px"
          (flag => [...document.querySelectorAll("#apps > *")].filter(icon => icon.offsetParent).filter(icon => {
            const box = icon.getBoundingClientRect()
            return (box.left < flag.right && box.right > flag.left && box.top < flag.bottom && box.bottom > flag.top) ||
              document.elementFromPoint(box.left + box.width / 2, box.top + box.height / 2)?.id === "flag-link"
          }).map(icon => icon.textContent.trim()))(document.getElementById("flag-link").getBoundingClientRect())
        JS
      end
    end
  end

  test "a window dragged to the top left covers the banner" do
    visit root_path
    left, top = page.evaluate_script("(box => [box.left, box.top].map(Math.round))(document.getElementById('welcomeheader').getBoundingClientRect())")
    page.driver.browser.action.move_to_location(left + 100, top + 10).click_and_hold
        .move_to_location(300, 100).move_to_location(100, 0).release.perform

    header = page.evaluate_script("(box => [box.left, box.top, box.bottom].map(Math.round))(document.getElementById('welcomeheader').getBoundingClientRect())")
    assert_operator header[1], :<, 85, "the header reaches the banner's height"
    assert_equal "welcomeheader", page.evaluate_script(<<~JS, [ header[0], 0 ].max + 30, (header[1] + header[2]) / 2)
      document.elementFromPoint(arguments[0], arguments[1]).closest(".windowheader").id
    JS
  end

  private
    # What a click at a point of the banner's drawing lands on.
    def element_on_banner(point)
      x, y = point
      page.evaluate_script("document.elementFromPoint(arguments[0], arguments[1]).id", x * 220.0 / 534, y * 85.0 / 207)
    end
end
