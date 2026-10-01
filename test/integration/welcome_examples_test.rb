require "test_helper"

# welcome.txt's example pets: a click on the picture opens the pet's page, as
# a click on its title does. The title stays the one link a keyboard or a
# screen reader meets.
class WelcomeExamplesTest < ActionDispatch::IntegrationTest
  test "each example's picture links to the same page as its title, and only the title takes focus" do
    get root_path
    cards = css_select("#welcome .image-card")
    assert_equal 4, cards.size
    cards.each do |card|
      title = card.at_css(".image-title a")
      picture = card.at_css("a.image-link")
      assert_equal title["href"], picture["href"]
      assert picture.at_css("img.grid-image"), "the picture sits inside its link"
      assert_equal "-1", picture["tabindex"]
      assert_equal "true", picture["aria-hidden"]
    end
  end
end
