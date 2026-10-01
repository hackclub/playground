require "application_system_test_case"

# The login chain in a real browser, with fake services: the login starts in
# login.exe, the dev login goes on to fake Hackatime by itself, in the top
# window, and lands on the desktop with ship.exe open. The desktop never
# renders inside a window.
class LoginFlowSystemTest < ApplicationSystemTestCase
  test "a login from inside login.exe links fake Hackatime and lands on the desktop" do
    visit root_path(open: "goal")
    click_reloading_the_desktop { within_frame(find(".login-frame")) { click_link "participant" } }

    assert_selector "#welcome", count: 1
    assert_no_selector "#window-login\\.exe", visible: :all
    within_frame(find(".ship-frame")) do
      assert_text "fake Hackatime linked"
      assert_no_text "isn't linked yet"
      assert_no_selector "#welcome"
    end
    assert_equal "fake", User.find_by!(hca_id: "ident!dev-participant").hackatime_access_token
  end

  test "login.exe shows the login's steps, and a login page of its own is login.exe on the wallpaper" do
    visit root_path(open: "goal")
    within_frame(find(".login-frame")) do
      assert_selector ".login-step.current", text: "Hack Club"
      assert_selector ".login-step:not(.current)", text: "Hackatime"
      # The window has a title bar of its own.
      assert_no_selector ".login-title"
      assert_equal "0px", page.evaluate_script("getComputedStyle(document.querySelector('.login')).borderTopWidth")
    end

    # A login that did not finish lands on the login's page, with why.
    visit auth_failure_path(strategy: "hack_club", message: "access_denied")
    assert_current_path login_path
    assert_selector ".login-title", exact_text: "login.exe"
    assert_selector "body > .flash.alert", exact_text: "login did not finish: access_denied"
    look = page.evaluate_script(<<~JS)
      (login => {
        const style = getComputedStyle(login), box = login.getBoundingClientRect()
        return {
          frame: [style.borderTopWidth, style.borderLeftWidth, style.borderTopColor],
          wallpaper: getComputedStyle(document.body).backgroundImage.includes("background"),
          centred: Math.abs(box.left + box.right - document.documentElement.clientWidth) <= 1,
          messageAbove: document.querySelector("body > .flash").getBoundingClientRect().bottom <= box.top
        }
      })(document.querySelector(".login"))
    JS
    assert_equal({ "frame" => [ "26px", "4px", "rgb(58, 112, 184)" ], "wallpaper" => true, "centred" => true, "messageAbove" => true }, look)
  end

  # The step submits itself as soon as it shows. Held here, it stays to be
  # looked at.
  test "the step between the two logins ticks Hack Club over, and with reduced motion shows it done at once" do
    browser = page.driver.browser
    hold = browser.execute_cdp("Page.addScriptToEvaluateOnNewDocument", source: "HTMLFormElement.prototype.submit = () => {}")
    [ "", "reduce" ].each do |motion|
      browser.execute_cdp("Emulation.setEmulatedMedia", features: [ { name: "prefers-reduced-motion", value: motion } ])
      visit dev_login_path(as: "participant")
      assert_current_path hackatime_step_path
      assert_selector ".login-step.current[aria-current=step]", text: "Hackatime"
      assert_button "continue to Hackatime (dev)"
      assert_equal motion.empty? ? "step-fill" : "none",
                   page.evaluate_script("getComputedStyle(document.querySelector('.just-done .step-node')).animationName")
      # Once any tick-over has run, Hack Club is done: a blue square with its
      # tick, no number, and a blue line on to Hackatime.
      done = page.evaluate_async_script(<<~JS)
        const finish = arguments[0]
        Promise.all(document.getAnimations().map(animation => animation.finished)).then(() => {
          const step = document.querySelector(".just-done"), style = selector => getComputedStyle(step.querySelector(selector))
          const number = style(".step-number")
          finish([style(".step-node").backgroundColor, style(".step-tick").visibility,
                  number.visibility === "visible" && number.opacity !== "0", getComputedStyle(step, "::after").backgroundColor])
        })
      JS
      assert_equal [ "rgb(58, 112, 184)", "visible", false, "rgb(58, 112, 184)" ], done, "motion: #{motion.presence || "full"}"
    end
  ensure
    browser.execute_cdp("Page.removeScriptToEvaluateOnNewDocument", identifier: hold["identifier"]) if hold
    browser.execute_cdp("Emulation.setEmulatedMedia", features: [ { name: "prefers-reduced-motion", value: "" } ])
  end

  test "after a declined Hackatime step, the retry in ship.exe links it in the top window" do
    visit dev_login_path(as: "participant", deny: 1)
    assert_selector "#welcome"
    within_frame(find(".ship-frame")) { assert_text "Hackatime did not link (access_denied)" }
    click_reloading_the_desktop { within_frame(find(".ship-frame")) { click_button "link Hackatime (dev)" } }

    assert_selector "#welcome", count: 1
    within_frame(find(".ship-frame")) do
      assert_text "fake Hackatime linked"
      assert_no_selector "#welcome"
    end
  end
end
