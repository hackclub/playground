require "application_system_test_case"

# The guide's "Make it your own" step: after Animate and drag, before
# Publish and ship, with each building block under its heading: its demo
# GIF, which opens the block's page in a new tab, while the guide stays
# where it was.
class NewSiteBuildingBlocksSystemTest < ApplicationSystemTestCase
  include NewSiteTests

  test "the step after Animate and drag shows each block under its heading, and its GIF opens its page in a new tab" do
    visit guide_page_path("animate")
    find(".guide-pager a.guide-next", text: "Make it your own").click
    assert_current_path "/guide/own"
    assert_selector ".hub-outline .outline-step > a[aria-current=page]", text: /\A6\s+Make it your own\z/
    assert_equal [ "Set up", "Build the scene", "Art and script", "Make it move", "Animate and drag", "Make it your own", "Publish and ship" ],
                 all(".hub-outline .outline-step > a").map { it.text.sub(/\A\d+\s*/, "") }
    assert_selector ".guide-pager a.guide-next", text: "Publish and ship"

    # One block after another, each its heading, then its GIF, the guide's
    # full width, which is the link.
    headings = all("section[aria-labelledby=your-own] > h3", count: BuildingBlock.all.size)
    assert_equal BuildingBlock.all.map(&:title), headings.map(&:text)
    links = all("section[aria-labelledby=your-own] > a.block-card", count: BuildingBlock.all.size)
    headings.zip(links).each_cons(2) do |(heading, link), (next_heading, _)|
      assert_operator link.rect.y, :>, heading.rect.y
      assert_operator next_heading.rect.y, :>, link.rect.y + link.rect.height - 1
    end
    assert_in_delta find("section[aria-labelledby=your-own]").rect.width, links.first.rect.width, 1
    assert_selector ".outline-step ol a", text: "Sound effect"

    link = find("a.block-card[href$='/guide/blocks/sound-effect']")
    assert_equal "_blank", link[:target]
    assert_match %r{/guide/blocks/sound-effect\z}, link[:href]
    assert_selector "a.block-card .block-open", text: "open ↗", count: BuildingBlock.all.size
    page_block = window_opened_by { link.find("img").click }
    within_window(page_block) do
      assert_current_path "/guide/blocks/sound-effect"
      assert_selector ".topbar .topbar-tab[aria-current]", text: "guide"
      assert_selector "article.guide h1", text: "Let's make some noise!"
      assert_selector "img.block-result"
      assert page.evaluate_script("document.querySelector('img.block-result').complete")
      assert_selector "p.block-back a[href='/guide/own#your-own']"
    end
    page_block.close
    assert_current_path "/guide/own"
  end

  test "on a phone each block's GIF takes the guide's width, and nothing scrolls sideways" do
    resize_viewport_to(390, 844) do
      visit "/clubs/own"
      gifs = all("section[aria-labelledby=your-own] > a.block-card", count: BuildingBlock.all.size)
      assert_in_delta find("section[aria-labelledby=your-own]").rect.width, gifs.first.rect.width, 1
      assert page.evaluate_script("document.documentElement.scrollWidth <= document.documentElement.clientWidth")

      visit "/clubs/blocks/particles"
      assert_selector "article.guide h1", text: "Let's make some hearts!"
      assert page.evaluate_script("document.documentElement.scrollWidth <= document.documentElement.clientWidth")
    end
  end
end
