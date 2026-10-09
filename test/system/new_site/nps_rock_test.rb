require "application_system_test_case"

# The new site's rock, in a real browser. A click opens feedback.exe, and a
# whole answer closes it with confetti and the rock's thanks, then the rock
# goes. A drag into the bin, Delete, or "not now" puts it away for 12 hours
# in this browser. A drag that ends anywhere else springs it back. On a
# phone a 0 to 10 strip stands in its place.
class NewSiteNpsRockSystemTest < ApplicationSystemTestCase
  include NewSiteTests
  ROCK = ".nps-ask .nps-rock".freeze
  POPUP = "dialog.nps-popup".freeze
  THANKS = [ "you rock!", "thanks!! you rock", "yay, thank you!" ].freeze
  PLEADING = [ "wait wait wait", "put me down 😭", "i have so much to live for", "i'll be good, i promise", "not the bin!!", "noooo",
               "i was gonna ask nicely!!", "this is rock abuse", "i can see the bin!!", "please please please", "tell my pet i loved them",
               "not like this", "i'm too young to be trash" ].freeze

  setup do
    NpsResponse.asking = true
    # The popup's form sends the page's CSRF token, which only renders with this on.
    ActionController::Base.allow_forgery_protection = true
    @user = User.find_by!(hca_id: "ident!dev-participant")
    CodingHour.create!(user: @user, hour: 1.day.ago.beginning_of_hour, seconds: 600)
  end

  teardown { ActionController::Base.allow_forgery_protection = false }

  test "a click opens feedback.exe, and a whole answer closes it with confetti, the rock's thanks, and then no rock" do
    log_in
    assert_selector ".nps-bubble-text u"
    find(ROCK).click
    within(POPUP) do
      assert_selector ".popup-title", exact_text: "feedback.exe"
      assert_selector ".nps-intro", exact_text: "how's playground going? be honest!"
      assert_button "submit", disabled: true
      choose "nps_rock_score_9", allow_label_click: true
      fill_in "what are we doing well?", with: "the guide"
      fill_in "what's something we can improve?", with: "more examples"
      click_button "submit"
    end
    assert_no_selector POPUP, visible: true
    assert_selector "canvas.confetti", visible: :all
    assert_includes THANKS, find(".nps-bubble-text").text
    assert_equal "thanks for the feedback", find(ROCK)["aria-label"]
    assert_no_selector ".nps-ask", wait: 6
    answer = NpsResponse.sole
    assert_equal [ @user, 9, "the guide", "more examples", "daily", nil ],
                 [ answer.user, answer.score, answer.doing_well, answer.improve, answer.source, answer.project ]

    visit guide_path
    assert_selector "#guide"
    assert_no_selector ".nps-ask", visible: :all
  end

  test "dragged into the bin, the rock pleads, the bin says et tu?, and it stays away for 12 hours" do
    log_in
    rock = find(ROCK)
    actions.move_to(rock.native).click_and_hold.move_by(-60, -20).perform
    assert_selector ".nps-rock.is-dragging"
    assert_selector ".nps-bin.is-shown"
    assert_includes PLEADING, find(".nps-bubble-text").text
    sleep 0.4
    x, y = evaluate_script("(b => [b.left + b.width / 2, b.top + b.height * 0.6].map(Math.round))(document.querySelector('.nps-bin-empty').getBoundingClientRect())")
    actions.move_to_location(x, y).perform
    assert_selector ".nps-bin.is-hot"
    actions.release.perform
    assert_selector ".nps-bin.is-full .nps-bin-say", text: "et tu?"
    assert_no_selector ".nps-ask", wait: 4
    assert_empty NpsResponse.all
    assert_operator dismissed_at, :>, (Time.current - 1.minute).to_f * 1000

    visit guide_path
    assert_selector "#guide"
    assert_selector ".nps-ask", visible: :hidden
    assert_no_selector ".nps-ask"
    dismissed_ago(12.hours + 1.minute)
    visit guide_path
    assert_selector ROCK
  end

  test "a drag that ends anywhere else springs back, and a click with no drag still opens the form" do
    log_in
    rock = find(ROCK)
    home = rock_box
    actions.move_to(rock.native).click_and_hold.move_by(-300, -200).perform
    assert_selector ".nps-rock.is-dragging"
    actions.release.perform
    assert_no_selector ".nps-rock.is-dragging"
    assert_no_selector ".nps-bin.is-shown"
    assert_no_selector POPUP, visible: true
    sleep 0.7
    assert_equal home, rock_box
    find(ROCK).click
    assert_selector POPUP, visible: true
    within(POPUP) { click_button "cancel" }
    assert_no_selector POPUP, visible: true
    assert_selector ROCK
    assert_nil dismissed_at_or_nil
  end

  test "Delete on the rock, or not now, puts it in the bin from the keyboard" do
    log_in
    find(ROCK).send_keys(:delete)
    assert_selector ".nps-bin.is-full .nps-bin-say", text: "et tu?"
    assert_no_selector ".nps-ask", wait: 5
    assert_not_equal "BODY", evaluate_script("document.activeElement.tagName"), "focus goes on to the page"

    forget_dismissal
    visit guide_path
    find(ROCK).send_keys(:tab)
    skip = find(".nps-rock-skip")
    assert_equal "not now, hide the rock for 12 hours", skip.text(:all).squish
    assert_operator evaluate_script("document.querySelector('.nps-rock-skip').getBoundingClientRect().width"), :>, 40, "it shows once it has focus"
    skip.send_keys(:enter)
    assert_no_selector ".nps-ask", wait: 5
    assert_empty NpsResponse.all
  end

  test "on a phone a 0 to 10 strip stands in the rock's place, and a number opens the form with it picked" do
    resize_viewport_to(390, 844) do
      log_in ".nps-strip"
      assert_selector ".nps-strip .nps-strip-box", count: 11
      assert_no_selector ROCK
      assert evaluate_script("document.documentElement.scrollWidth <= innerWidth"), "nothing runs off the side"
      find(".nps-strip-box", exact_text: "7").click
      within(POPUP) do
        assert find("#nps_rock_score_7", visible: :all).checked?
        fill_in "what are we doing well?", with: "the videos"
        fill_in "what's something we can improve?", with: "nothing"
        click_button "submit"
      end
      assert_includes THANKS, find(".nps-strip-thanks").text
      assert_no_selector ".nps-ask", wait: 6
      assert_equal 7, NpsResponse.sole.score
    end
  end

  private

  def log_in(asks = ROCK)
    visit dev_login_path(as: "participant")
    assert_selector "#guide"
    assert_selector asks
  end

  # One builder for a whole drag, so the button stays held between its steps.
  def actions = (@actions ||= page.driver.browser.action)

  def rock_box = evaluate_script("(r => [r.left, r.top].map(Math.round))(document.querySelector('.nps-rock').getBoundingClientRect())")

  def store = "playground-nps-asked:#{@user.id}"
  def dismissed_at_or_nil = page.evaluate_script("localStorage.getItem(arguments[0])", store)
  def dismissed_at = Integer(dismissed_at_or_nil)
  def dismissed_ago(span) = page.execute_script("localStorage.setItem(arguments[0], String(Date.now() - arguments[1]))", store, (span.to_f * 1000).round)
  def forget_dismissal = page.execute_script("localStorage.removeItem(arguments[0])", store)
end
