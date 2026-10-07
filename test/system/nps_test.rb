require "application_system_test_case"

# nps.exe on the desktop, and the NPS questions in a pet's ship window. A
# participant with no answer from the last 12 hours is due: nps.exe opens
# by itself, at most once every 12 hours in a browser, so a close keeps it
# shut that long. A ship needs an answer too.
class NpsSystemTest < ApplicationSystemTestCase
  WINDOW = "#window-nps\\.exe".freeze
  READY = { description: "a pebble that rolls across your screen", code_url: "https://github.com/pet/rock",
            ship_message_url: "https://hackclub.slack.com/archives/C0C51NCK1DG/p1759012345678901", playable_url: "https://pet.itch.io/rock", hackatime_projects: [ "rock-pet" ],
            screenshots: [ { "id" => "shot", "key" => "shot.webp", "url" => "https://playground.hackclub-assets.com/shot.webp" } ] }.freeze

  setup do
    NpsResponse.asking = true
    # The form posts with the page's CSRF token, which only renders with this on.
    ActionController::Base.allow_forgery_protection = true
  end

  teardown do
    ActionController::Base.allow_forgery_protection = false
  end

  test "nps.exe opens by itself in front, sends only a whole answer, and closes with confetti" do
    user = log_in_with_time
    assert_selector "#{WINDOW} .headertext", exact_text: "nps.exe"
    assert_front "window-nps.exe"
    assert_selector "[data-key='nps.exe']", text: "nps.exe"

    within_frame(find("#{WINDOW} iframe")) do
      assert_selector "h2", exact_text: "how's playground going? be honest!"
      assert_button "submit", disabled: true
      assert_text "pick a number and fill in the * ones to send."
      # The score boxes take the arrow keys, as a row of radio buttons does.
      find("#nps_response_score_5", visible: :all).send_keys(:right, :right, :right)
      assert find("#nps_response_score_8", visible: :all).checked?
      fill_in "what are we doing well?", with: "the guide"
      assert_button "submit", disabled: true
      fill_in "what's something we can improve?", with: "   "
      assert_button "submit", disabled: true
      fill_in "what's something we can improve?", with: "more examples"
      assert_no_text "pick a number and fill in"
      click_button "submit"
    end
    # The window closes at once, and confetti bursts on the desktop, takes
    # no clicks, and goes.
    assert_no_selector WINDOW
    assert_selector "canvas.confetti", visible: :all
    confetti = evaluate_script("(c => [getComputedStyle(c).pointerEvents, ...Object.values(c.getBoundingClientRect().toJSON()).slice(0, 4).map(Math.round)])(document.querySelector('canvas.confetti'))")
    assert_equal [ "none", 0, 0, *evaluate_script("[innerWidth, innerHeight]") ], confetti, "the whole screen, and no clicks"
    assert_no_selector "canvas.confetti", visible: :all, wait: 4
    answer = NpsResponse.sole
    assert_equal [ user, 8, "the guide", "more examples", "", "daily" ],
                 [ answer.user, answer.score, answer.doing_well, answer.improve, answer.anything_else.to_s, answer.source ]

    forget_nps_asks
    visit root_path
    assert_selector "#welcome"
    assert_no_selector WINDOW, wait: 4
    # Its icon opens it any time, on a fresh form.
    find("[data-key='nps.exe']").click
    within_frame(find("#{WINDOW} iframe")) do
      assert_button "submit", disabled: true
      assert_equal "", find_field("what are we doing well?").value
    end
  end

  test "with less motion asked for, a sent answer closes nps.exe with no confetti" do
    page.driver.browser.execute_cdp("Emulation.setEmulatedMedia", features: [ { name: "prefers-reduced-motion", value: "reduce" } ])
    log_in_with_time
    within_frame(find("#{WINDOW} iframe")) do
      choose "nps_response_score_3", allow_label_click: true
      fill_in "what are we doing well?", with: "the guide"
      fill_in "what's something we can improve?", with: "fewer windows"
      click_button "submit"
    end
    assert_no_selector WINDOW
    assert_equal 0, evaluate_script("document.querySelectorAll('canvas.confetti').length")
    assert_equal 1, NpsResponse.count
  ensure
    page.driver.browser.execute_cdp("Emulation.setEmulatedMedia", features: [])
  end

  test "a cancel or a close keeps nps.exe shut for 12 hours" do
    log_in_with_time
    within_frame(find("#{WINDOW} iframe")) { click_link "cancel" }
    assert_no_selector WINDOW
    visit root_path
    assert_selector "#welcome"
    assert_no_selector WINDOW, wait: 4

    asked_ago(12.hours + 1.minute)
    visit root_path
    assert_selector WINDOW
    find("#{WINDOW} .windowclose").click
    assert_operator asked_at, :>, (Time.current - 1.minute).to_f * 1000

    asked_ago(12.hours - 1.minute)
    visit root_path
    assert_selector "#welcome"
    assert_no_selector WINDOW, wait: 4
    assert_empty NpsResponse.all
  end

  test "on a phone nps.exe fills the width, with the eleven boxes in one row" do
    resize_viewport_to(390, 844) do
      log_in_with_time
      within_frame(find("#{WINDOW} iframe")) do
        tops = evaluate_script("[...document.querySelectorAll('.nps-box')].map(box => Math.round(box.getBoundingClientRect().top))")
        assert_equal 11, tops.size
        assert_equal 1, tops.uniq.size
        assert evaluate_script("document.documentElement.scrollWidth <= innerWidth"), "nothing runs off the side"
        assert_operator evaluate_script("document.querySelector('.nps-box').getBoundingClientRect().width"), :>=, 24
      end
      box = page.evaluate_script("(b => [b.left, b.right])(document.querySelector(arguments[0]).getBoundingClientRect())", WINDOW)
      assert_operator box[0], :>=, 0
      assert_operator box[1], :<=, 390
    end
  end

  test "with no answer in the last 12 hours, the ship list asks in a step that saves in place" do
    # A newcomer with no Hackatime time: nps.exe stays shut, and the ship asks anyway.
    user = log_in_as("participant")
    user.update!(hackatime_access_token: "fake")
    project = user.projects.create!(READY.merge(name: "rock"))
    assert_selector "[data-key='nps.exe']"
    assert_no_selector WINDOW, wait: 4

    visit root_path(open: "goal")
    within_frame(find(".ship-frame")) { find_link("rock", exact_text: true).send_keys(:enter) }
    within_frame(find("#window-pet-#{project.id} iframe")) { click_link "ship" }
    window = "#window-ship-#{project.id}"
    within_frame(find("#{window} iframe")) do
      assert_selector "#ship-check-nps.todo", text: "tell us how playground is going"
      assert_selector "#ship-checks .row button[disabled]", exact_text: "ship"
      assert_text "fix these first"
      within("#ship-check-nps") do
        assert_button "send", disabled: true
        assert_text "pick a number and fill in the * ones."
        # A pick saves nothing yet, as the answer is whole only when sent.
        choose "nps_response_score_10", allow_label_click: true
        fill_in "what are we doing well?", with: "the reviews"
        fill_in "what's something we can improve?", with: "nothing"
        fill_in "anything else you want to tell us?", with: "hi froppii"
        assert_empty NpsResponse.all
        click_button "send"
      end
      assert_selector "#ship-check-nps.ok .icon", exact_text: "✓"
      assert_selector "#ship-check-nps p.fix", exact_text: "thanks! 🪨"
      ship = find("#ship-checks .row button:not([disabled])")
      assert_match(/\Aship \d+h \d+m\z/, ship.text)
      accept_confirm("ship rock? have you read the submission requirements? a reviewer checks your hours next.") { ship.click }
    end
    # The ship carried an answer, so it ends in confetti on the desktop.
    assert_selector "canvas.confetti", visible: :all, wait: 10
    assert_no_selector window, wait: 10
    assert_no_selector "canvas.confetti", visible: :all, wait: 4
    assert project.ships.sole.pending?
    answer = NpsResponse.sole
    assert_equal [ 10, "hi froppii", "ship", project ], [ answer.score, answer.anything_else, answer.source, answer.project ]
  end

  private

  # The development participant, made first with a minute of Hackatime time
  # and more, so nps.exe asks by itself at the login's desktop.
  def log_in_with_time
    user = User.create!(hca_id: "ident!dev-participant", email: "participant@example.com", first_name: "Participant", last_name: "Dev",
                        verification_status: "verified", ysws_eligible: true)
    CodingHour.create!(user:, hour: 1.day.ago.beginning_of_hour, seconds: 600)
    log_in_as("participant")
  end

  def asked_store = "playground-nps-asked:#{User.find_by!(hca_id: "ident!dev-participant").id}"
  def asked_at = page.evaluate_script("Number(localStorage.getItem(arguments[0]))", asked_store)
  def asked_ago(span) = page.execute_script("localStorage.setItem(arguments[0], String(Date.now() - arguments[1]))", asked_store, (span.to_f * 1000).round)
  def forget_nps_asks = page.execute_script("localStorage.removeItem(arguments[0])", asked_store)

  def front_window
    page.evaluate_script(<<~JS)
      [...document.querySelectorAll(".window")].filter(win => getComputedStyle(win).display !== "none")
        .sort((a, b) => getComputedStyle(a).zIndex - getComputedStyle(b).zIndex).pop().id
    JS
  end

  def assert_front(id)
    page.document.synchronize { raise Capybara::ExpectationNotMet, "#{front_window} is in front" unless front_window == id }
  end
end
