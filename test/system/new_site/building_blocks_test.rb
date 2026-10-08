require "application_system_test_case"

# The guide's "Make it your own" step: after Animate and drag, before
# Publish and ship, with a card for each building block. A card opens the
# block's page in a new tab, and the guide stays where it was.
class NewSiteBuildingBlocksSystemTest < ApplicationSystemTestCase
  include NewSiteTests

  test "the step after Animate and drag lists a card for each block, and a card opens its page in a new tab" do
    visit guide_page_path("animate")
    find(".guide-pager a.guide-next", text: "Make it your own").click
    assert_current_path "/guide/own"
    assert_selector ".hub-outline .outline-step > a[aria-current=page]", text: /\A6\s+Make it your own\z/
    assert_equal [ "Set up", "Build the scene", "Art and script", "Make it move", "Animate and drag", "Make it your own", "Publish and ship" ],
                 all(".hub-outline .outline-step > a").map { it.text.sub(/\A\d+\s*/, "") }
    assert_selector ".guide-pager a.guide-next", text: "Publish and ship"

    cards = all("#your-own ~ .block-cards a.block-card", count: BuildingBlock.all.size)
    assert_equal BuildingBlock.all.map(&:title), cards.map { it.find(".block-card-title").text[/\A[^↗]+/].strip }
    card = cards.first
    assert_equal "_blank", card[:target]
    assert_match %r{/guide/blocks/sound-effect\z}, card[:href]

    page_block = window_opened_by { card.click }
    within_window(page_block) do
      assert_current_path "/guide/blocks/sound-effect"
      assert_selector "article.guide h1", text: "Let's make some noise!"
      assert_selector "img.block-result"
      assert page.evaluate_script("document.querySelector('img.block-result').complete")
      assert_selector "p.block-back a[href='/guide/own#your-own']"
    end
    page_block.close
    assert_current_path "/guide/own"
  end

  test "on a phone each card takes the whole row, so its GIF is big, and nothing scrolls sideways" do
    resize_viewport_to(390, 844) do
      visit "/clubs/own"
      cards = all(".block-cards a.block-card", count: BuildingBlock.all.size)
      assert_operator cards[1].rect.y, :>, cards[0].rect.y
      assert_equal cards[0].rect.x, cards[1].rect.x
      assert_operator cards[0].find("img").rect.width, :>, 300
      assert page.evaluate_script("document.documentElement.scrollWidth <= document.documentElement.clientWidth")

      visit "/clubs/blocks/particles"
      assert_selector "article.guide h1", text: "Let's make some hearts!"
      assert page.evaluate_script("document.documentElement.scrollWidth <= document.documentElement.clientWidth")
    end
  end
end
