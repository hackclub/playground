require "application_system_test_case"

# The sponsor's name shows on the landing page without scrolling, as Hack
# Club's rules ask, and nothing covers it as the page opens. On a desktop his
# icon is the credit: it opens his Slack profile in a new tab, as the
# required links open their sites. On a phone the text row at the top credits
# him instead, and the icons it stands in for do not show.
class SponsorCreditTest < ApplicationSystemTestCase
  LINK_ICONS = [ "Hack Club", "Terms & Privacy", "Fulfillment", "Security", "armand.sponsor" ].freeze

  test "on a desktop, armand.sponsor links to his Slack in a new tab, wears the arrow, and shows uncovered" do
    visit root_path
    icon = find("a.app", exact_text: "armand.sponsor")
    assert_equal [ ApplicationHelper::SPONSOR_URL, "_blank", "noopener" ], [ icon[:href], icon[:target], icon[:rel] ]
    assert_selector "a.app", exact_text: "armand.sponsor" do |link|
      link.has_selector?(".shortcut", visible: :all)
    end
    assert_includes icon.find(".appicon")[:src], "/landing/sponsor-"
    assert uncovered?(icon.find(".appicon")), "welcome.txt leaves the sponsor's icon showing"
    LINK_ICONS.each { |label| assert_selector ".app", exact_text: label }
    assert_no_text "sponsored by"

    # A click follows the link and opens no window. A listener stops it
    # after the icon's own, which keeps the test off the network.
    page.execute_script(<<~JS)
      document.addEventListener("click", event => {
        if (!event.target.closest("a.app")) return
        window.followed = !event.defaultPrevented
        event.preventDefault()
      })
    JS
    icon.click
    assert page.evaluate_script("window.followed")
    assert_no_selector "#window-armand\\.sponsor", visible: :all
    assert_equal 1, windows.size
  end

  test "on a phone, the text row credits him, without scrolling and uncovered, in place of the link icons" do
    [ [ 360, 740 ], [ 390, 844 ], [ 430, 932 ] ].each do |width, height|
      at = "at #{width}x#{height}"
      resize_viewport_to(width, height) do
        visit root_path
        assert_text "sponsored by Armand"
        name = find("#credit-links a", exact_text: "Armand")
        assert_equal ApplicationHelper::SPONSOR_URL, name[:href]
        assert on_screen?(name), "his name shows without scrolling #{at}"
        assert uncovered?(name), "welcome.txt leaves his name showing #{at}"
        assert_not row_over_flag?, "the row lies clear of the flag #{at}"
        LINK_ICONS.each { |label| assert_no_selector ".app", exact_text: label }
        assert_equal LINK_ICONS.size, all("a.app, .app[data-key='armand.sponsor']", visible: :all).size
        assert_selector ".app", exact_text: "welcome.txt"
      end
    end
  end

  test "without scripts on a phone, the row credits him, clear of the flag" do
    page.driver.browser.execute_cdp("Emulation.setScriptExecutionDisabled", value: true)
    resize_viewport_to(390, 844) do
      visit root_path
      assert_text "sponsored by Armand"
      assert on_screen?(find("#credit-links a", exact_text: "Armand")), "his name shows without scrolling"
      assert_not row_over_flag?, "the row lies clear of the flag"
    end
  ensure
    page.driver.browser.execute_cdp("Emulation.setScriptExecutionDisabled", value: false)
  end

  test "a saved window state that names the old sponsor window loads cleanly, and drops it" do
    page.driver.browser.execute_cdp("Page.addScriptToEvaluateOnNewDocument", source: <<~JS).then { @script = it["identifier"] }
      window.pageErrors = []
      addEventListener("error", event => pageErrors.push(event.message))
    JS
    # Saved from a page that saves no windows, so the desktop's own save,
    # once its login.exe is in, cannot write over it.
    visit login_path
    page.execute_script(<<~JS)
      localStorage.setItem("playground-window-state:visitor", JSON.stringify([
        { kind: "app", id: "armand.sponsor", place: { left: 400, top: 200 } },
        { kind: "app", id: "guide.txt", place: { left: 500, top: 260 } }
      ]))
    JS
    visit root_path
    assert_selector "#window-guide\\.txt"
    assert_no_selector "#window-armand\\.sponsor", visible: :all
    assert_selector "a.app", exact_text: "armand.sponsor"
    assert_empty page.evaluate_script("pageErrors")
    # guide.txt comes back, saved now as the guide's own kind of window.
    page.document.synchronize do
      saved = page.evaluate_script("JSON.parse(localStorage.getItem('playground-window-state:visitor')).map(entry => [entry.kind, entry.id])")
      raise Capybara::ExpectationNotMet, "saved #{saved}" unless saved == [ [ "guide", nil ] ]
    end
  ensure
    page.driver.browser.execute_cdp("Page.removeScriptToEvaluateOnNewDocument", identifier: @script) if @script
  end

  private
    # Whether the text row's box and the flag's box overlap at all.
    def row_over_flag?
      page.evaluate_script(<<~JS)
        (([row, flag]) => row.left < flag.right && row.right > flag.left && row.top < flag.bottom && row.bottom > flag.top)(
          ["credit-links", "background-flag"].map(id => document.getElementById(id).getBoundingClientRect()))
      JS
    end

    def on_screen?(element)
      page.evaluate_script("(box => box.top >= 0 && box.left >= 0 && box.bottom <= innerHeight && box.right <= innerWidth)(arguments[0].getBoundingClientRect())", element)
    end

    # Whether a press on the middle of the element lands on it.
    def uncovered?(element)
      page.evaluate_script("(el => (box => el.contains(document.elementFromPoint(box.left + box.width / 2, box.top + box.height / 2)))(el.getBoundingClientRect()))(arguments[0])", element)
    end
end
