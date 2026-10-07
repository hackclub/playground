require "application_system_test_case"

# The active pet switch in a real browser: a pick draws its own part of the
# guide again in place, and the next step card follows. It works by
# keyboard, and Escape closes it.
class NewSiteActivePetSystemTest < ApplicationSystemTestCase
  include NewSiteTests
  setup do
    # The switch's forms send the page's CSRF token, which only renders with this on.
    ActionController::Base.allow_forgery_protection = true
    visit dev_login_path(as: "participant")
    assert_selector "#guide"
    @user = User.find_by!(hca_id: "ident!dev-participant")
    @user.projects.create!(name: "rock", hackatime_projects: [ "rock-pet" ])
    @user.projects.create!(name: "pebble")
  end

  teardown { ActionController::Base.allow_forgery_protection = false }

  test "a pick from the pick step switches it in place, and the next step card follows" do
    visit "/guide/scene#pick-step"
    assert_selector "#pick-step .pet-switch summary strong", text: "pebble"
    # The card hides while its part of the guide, here the pick step, is on
    # screen. pebble has no Hackatime project, so the card goes to the pick.
    assert_equal "link pebble to Hackatime", find("#hub-next #next-title", visible: :all).text(:all)
    page.execute_script("document.documentElement.dataset.stillHere = ''")

    find("#pick-step .pet-switch summary").click
    within("#pick-step .pet-switch-menu") { click_button "rock" }
    assert_selector "#pick-step .pet-switch summary strong", text: "rock"
    assert_selector "#pick-step .guide-do-title", text: /\AHackatime counts rock/
    assert_selector "#hub-next #next-title", visible: :all, exact_text: "ship rock"
    assert_selector "#hub-next .pet-switch summary strong", visible: :all, text: "rock"
    assert page.evaluate_script("'stillHere' in document.documentElement.dataset"), "the switch redrew its part, with no new page"
  end

  test "by keyboard, the Ship it step's switch opens, closes on Escape, and switches the pet" do
    visit "/guide/publish#ship"
    summary = find("#ship-step .pet-switch summary", text: "pebble")
    summary.send_keys(:enter)
    assert_selector "#ship-step .pet-switch[open]"
    page.send_keys(:escape)
    assert_no_selector "#ship-step .pet-switch[open]"
    assert_equal "SUMMARY", page.evaluate_script("document.activeElement.tagName")

    page.send_keys(:enter, :tab)
    assert_equal "rock", page.evaluate_script("document.activeElement.textContent.trim()")
    page.send_keys(:enter)
    assert_selector "#ship-step .pet-switch summary strong", text: "rock"
    assert_selector "#ship-step .guide-do-title", text: "ship rock"
    assert_selector "#hub-next #next-title", visible: :all, exact_text: "ship rock"
    assert_equal "SUMMARY", page.evaluate_script("document.activeElement.tagName"), "focus comes back to the switch"
  end
end
