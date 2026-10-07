require "application_system_test_case"

# The new site's footer link to the old desktop in a real browser: it asks
# first in a small window, which Escape, the X, and "stay here" close, by
# mouse or keyboard. "switch" goes to the old desktop, whose icon comes back.
class NewSiteClassicSwitchSystemTest < ApplicationSystemTestCase
  include NewSiteTests

  setup do
    # The switch's form sends the page's CSRF token, which only renders with this on.
    ActionController::Base.allow_forgery_protection = true
    visit dev_login_path(as: "participant")
    assert_selector "#guide"
  end

  teardown { ActionController::Base.allow_forgery_protection = false }

  test "the footer's link asks first, and Escape, the X, and stay here each keep the new site" do
    open_question
    assert_equal "stay here", page.evaluate_script("document.activeElement.textContent.trim()"), "a stray Enter switches nothing"
    find("#classic-dialog").send_keys(:escape)
    assert_no_selector "#classic-dialog[open]"

    open_question
    find("#classic-dialog .classic-x").click
    assert_no_selector "#classic-dialog[open]"

    open_question
    page.driver.browser.action.send_keys(:enter).perform
    assert_no_selector "#classic-dialog[open]"
    assert_selector "body.new-site"
    assert_equal "/guide", page.evaluate_script("location.pathname")
  end

  test "switch goes to the old desktop, and its icon comes back to the new site" do
    open_question
    within("#classic-dialog") { click_button "switch" }
    assert_selector "#welcome"
    assert_no_selector "body.new-site"
    find("#back-to-new-site button", text: "new playground").click
    assert_selector "body.new-site .home-window"
    assert_no_selector "#back-to-new-site"
  end

  test "on a phone the question fits the screen" do
    resize_viewport_to(390, 844) do
      open_question
      box = page.evaluate_script("document.querySelector('#classic-dialog').getBoundingClientRect().toJSON()")
      assert_operator box["left"], :>=, 0
      assert_operator box["right"], :<=, 390
      assert_selector "#classic-dialog button", text: "switch"
      assert_selector "#classic-dialog button", text: "stay here"
    end
  end

  private

  def open_question
    find(".footbar a.footbar-classic").click
    assert_selector "#classic-dialog[open]"
    assert_selector "#classic-dialog p", text: "switch to the old desktop? you can switch back anytime"
  end
end
