require "application_system_test_case"

# The top bar in a real browser: a strip of the landing's sky, still while
# the page scrolls over it, the logo's drawing 84px tall, the open tab
# standing over the blue line so it opens onto the page, and on a phone the
# links beside the logo and the tabs under both, with no sideways scroll.
class NewSiteTopbarSystemTest < ApplicationSystemTestCase
  include NewSiteTests
  # Where the parts of the top bar sit, in CSS pixels.
  def topbar_layout
    page.evaluate_script(<<~JS)
      (() => {
        const box = s => document.querySelector(s).getBoundingClientRect()
        const bar = box(".topbar"), line = parseFloat(getComputedStyle(document.querySelector(".topbar")).borderBottomWidth)
        const open = document.querySelector(".topbar-tab[aria-current]")
        return {
          scroll: document.documentElement.scrollWidth, width: document.documentElement.clientWidth,
          logo: box(".topbar-home img").height, logoBottom: box(".topbar-home").bottom,
          sky: getComputedStyle(document.body, "::before").backgroundImage,
          lineTop: bar.bottom - line, barBottom: bar.bottom,
          openBottom: open && open.getBoundingClientRect().bottom,
          openColor: open && getComputedStyle(open).backgroundColor,
          pageColor: getComputedStyle(document.body).backgroundColor,
          otherBottom: box(".topbar-tab:not([aria-current])").bottom,
          tabsTop: box(".topbar-tabs").top, linksBottom: box(".topbar-links").bottom
        }
      })()
    JS
  end

  setup do
    visit dev_login_path(as: "participant")
    assert_selector ".topbar"
  end

  test "on a wide screen the sky is behind the logo, whose drawing is 84px, and the open tab covers the line where the other tab stands on it" do
    [ guide_path, projects_path ].each do |path|
      visit path
      layout = topbar_layout
      assert_match %r{/assets/landing/background-\w+\.png}, layout["sky"], path
      # The picture is 105px, with a clear margin round its 84px drawing.
      assert_equal 105, layout["logo"].round, path
      assert_operator layout["scroll"], :<=, layout["width"], path
      # The open tab reaches down through the line, in the page's colour.
      assert_in_delta layout["barBottom"], layout["openBottom"], 0.5, path
      assert_equal layout["pageColor"], layout["openColor"], path
      # The other tab ends where the line starts.
      assert_in_delta layout["lineTop"], layout["otherBottom"], 0.5, path
    end
  end

  test "on a phone the links sit beside the logo, the tabs under both, and nothing scrolls sideways" do
    resize_viewport_to(390, 844) do
      [ guide_path, projects_path, requirements_path ].each do |path|
        visit path
        layout = topbar_layout
        assert_operator layout["scroll"], :<=, layout["width"], path
        assert_equal 87, layout["logo"].round, path
        assert_operator layout["tabsTop"], :>=, layout["logoBottom"], path
        assert_operator layout["linksBottom"], :<=, layout["tabsTop"], path
      end
    end
  end

  test "the sky stays still while the top bar scrolls away, and the page slides over it" do
    resize_viewport_to(1440, 900) do
      visit guide_path
      sky = -> { page.evaluate_script(<<~JS) }
        (() => {
          const sky = getComputedStyle(document.body, "::before"), line = document.querySelector(".topbar").getBoundingClientRect().bottom
          const top = document.elementFromPoint(innerWidth - 40, 20)
          return { position: sky.position, top: sky.top, line, sheetAtTop: !!top.closest(".sheet"), sheet: getComputedStyle(document.querySelector(".sheet")).backgroundColor,
                   page: getComputedStyle(document.body).backgroundColor }
        })()
      JS
      at_rest = sky.()
      assert_equal [ "fixed", "0px" ], at_rest.values_at("position", "top")
      assert_not at_rest["sheetAtTop"], "at rest the top of the window is the top bar"
      page.execute_script("scrollTo(0, 300)")
      scrolled = sky.()
      assert_equal [ "fixed", "0px" ], scrolled.values_at("position", "top")
      assert_in_delta at_rest["line"] - 300, scrolled["line"], 0.5
      assert scrolled["sheetAtTop"], "scrolled, the page covers the top of the window"
      assert_equal scrolled["page"], scrolled["sheet"], "the sheet is the page's own colour"
    end
  end

  test "an admin's admin link stands in the stack, the same size and on the same white as sign out" do
    visit dev_login_path(as: "admin")
    visit guide_path
    links = page.evaluate_script(<<~JS)
      [...document.querySelectorAll(".topbar-links > a, .topbar-links .linkish")].map(e => {
        const s = getComputedStyle(e)
        return [e.textContent.trim(), s.fontSize, s.backgroundColor, Math.round(e.getBoundingClientRect().height)]
      })
    JS
    assert_equal [ "admin", "sign out", "help in #playground" ], links.map(&:first)
    assert_equal 1, links.map { it.drop(1) }.uniq.size, "every link in the stack looks the same: #{links.inspect}"
  end

  # Where the footer sits against the window and the page's content.
  def footer_layout
    page.evaluate_script(<<~JS)
      (() => {
        const d = document.documentElement, foot = document.querySelector(".footbar").getBoundingClientRect()
        const content = document.querySelector("main.page").lastElementChild.getBoundingClientRect()
        return { scrollHeight: d.scrollHeight, clientHeight: d.clientHeight, footTop: foot.top + scrollY,
                 footBottom: foot.bottom + scrollY, contentBottom: content.bottom + scrollY }
      })()
    JS
  end

  test "on a short page the footer sits at the window's bottom with no scroll, and on a long page it follows the content" do
    # The requirements fit a wide window, and run past a phone's.
    { [ 1440, 900 ] => [ projects_path, requirements_path ], [ 390, 844 ] => [ projects_path ] }.each do |(width, height), short|
      resize_viewport_to(width, height) do
        short.each do |path|
          visit path
          footer = footer_layout
          assert_equal footer["clientHeight"], footer["scrollHeight"], "#{path} scrolls at #{width}"
          assert_in_delta height, footer["footBottom"], 0.5, "#{path} at #{width}"
        end
        visit guide_path
        footer = footer_layout
        assert_operator footer["scrollHeight"], :>, height
        assert_in_delta footer["scrollHeight"], footer["footBottom"], 0.5, "the footer ends the guide at #{width}"
        assert_in_delta footer["contentBottom"] + 20, footer["footTop"], 0.5, "the footer follows the guide at #{width}"
      end
    end
  end
end
