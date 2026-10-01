require "application_system_test_case"

# A reload brings back the desktop's open windows in this browser: the same
# windows, from the back to the front, where they were, each framed one on
# the page it showed. The state belongs to the account signed in, or to no
# account, and a window comes back only if it still can.
class WindowStateTest < ApplicationSystemTestCase
  setup do
    @user = log_in_as("participant")
    @rock = @user.projects.create!(name: "rock", description: "naps on your windows")
  end

  test "a reload brings back the open windows, front to back, where they were, each on its page" do
    open_and_reload
  end

  test "at 1024x768 a reload brings back the open windows, front to back, where they were, each on its page" do
    resize_viewport_to(1024, 768) { open_and_reload }
  end

  test "a reload brings welcome.txt and guide.txt back as tall as a fresh open, their content showing" do
    forget_open_windows
    visit root_path
    press icon("guide.txt")
    # Between the bottom groups, where a reload may bring it back whole: a
    # window that comes back by itself never covers the required links. It
    # moves once it has fitted its page and been placed.
    page.document.synchronize do
      raise Capybara::ExpectationNotMet, "guide.txt is still being placed" if page.evaluate_script("!!document.querySelector('.window[data-placing]')")
    end
    page.execute_script("Object.assign(document.getElementById('window-guide.txt').style, { left: '330px', top: '10px' })")
    # welcome.txt in front of guide.txt: a focus in a window raises it.
    page.execute_script("document.querySelector('#welcome .windowclose').focus()")
    assert_equal "welcome", front_window
    fresh = sizes
    assert_equal %w[welcome window-guide.txt], fresh.keys.sort

    visit root_path
    page.document.synchronize do
      raise Capybara::ExpectationNotMet, "#{sizes} is not #{fresh}" unless sizes == fresh
    end
    # The middle of welcome.txt's text is welcome.txt's own, not a window over it.
    assert_equal "welcome", page.evaluate_script(<<~JS)
      (box => document.elementFromPoint(box.left + box.width / 2, box.top + box.height / 2).closest(".window").id)(document.querySelector("#welcome .windowcontent").getBoundingClientRect())
    JS
  end

  test "a closed window leaves the saved state at once, and a reload leaves it closed" do
    visit root_path
    press icon("guide.txt")
    assert_saved '"kind":"guide"'
    press find("#window-guide\\.txt .windowclose")
    press find("#welcome .windowclose")
    assert_saved '"kind":"guide"', present: false
    visit root_path
    assert_selector "#window-goal\\.exe"
    assert_no_selector "#window-guide\\.txt"
    assert_no_selector "#welcome"
  end

  test "a pet deleted since the last visit takes its window out of the saved state" do
    visit root_path
    press icon("rock")
    within_frame(pet_frame) { assert_selector "h2", text: "rock" }
    assert_saved "pet"
    @rock.destroy!
    visit root_path
    assert_selector "#window-goal\\.exe"
    assert_no_selector pet_window, visible: :all
    assert_saved "pet", present: false
  end

  test "only known windows on their own pages come back, and one whose page is an error closes" do
    visit root_path
    save_state [ { kind: "guide", page: guide_path },
                 { kind: "guide", page: dashboard_path },
                 { kind: "redeem", page: new_redemption_path(goal_key: "no-such-goal") },
                 { kind: "pet", id: @rock.id, page: checks_project_path(@rock) },
                 { kind: "pet", id: @rock.id + 1000, page: project_path(@rock.id + 1000) },
                 { kind: "app", id: "goal.exe" },
                 { kind: "app", id: "ship.exe" },
                 { kind: "clock" } ]
    visit root_path
    within_frame(find("#window-guide\\.txt iframe")) { assert_selector "h1", text: "Build a virtual pet in Godot" }
    # The redeem window's page is a 404, so it closes once it loads.
    assert_selector "#window-redeem-no-such-goal", visible: :hidden
    assert_no_selector "#window-redeem-no-such-goal"
    assert_no_selector pet_window, visible: :all
    assert_no_selector "#window-goal\\.exe", visible: :all
    assert_no_selector "#welcome"
    page.document.synchronize do
      kept = saved_state.map { [ it["kind"], it["id"] ] }
      raise Capybara::ExpectationNotMet, "#{kept} is saved" unless kept == [ [ "guide", nil ] ]
    end
  end

  test "a log out shows the visitor's desktop, and another account never gets the pet's windows" do
    visit root_path
    press icon("rock")
    within_frame(pet_frame) { assert_selector "h2", text: "rock" }
    assert_saved "pet"

    click_reloading_the_desktop { within_frame(goal) { press find_button("log out") } }
    assert_selector "#welcome"
    assert_no_selector ".app.pet"
    assert_no_selector pet_window, visible: :all

    log_in_as("admin")
    assert_selector "#window-goal\\.exe"
    assert_no_selector pet_window, visible: :all

    # The participant's own login brings the pet's window back, behind ship.exe.
    log_in_as("participant")
    within_frame(pet_frame) { assert_selector "h2", text: "rock" }
    assert_equal "window-goal.exe", front_window
  end

  test "a login opens ship.exe on its dashboard in front, and its message shows there only" do
    visit root_path
    press icon("rock")
    within_frame(pet_frame) { press find_link("edit") }
    within_frame(pet_frame) { assert_selector "h2", text: "edit rock" }
    within_frame(goal) { press find_link("+ new pet") }
    within_frame(goal) { assert_selector "h2", text: "new pet" }
    assert_saved "/projects/new"

    # Linking Hackatime lands on the desktop with ship.exe asked for and a
    # message, as a login does.
    click_reloading_the_desktop do
      page.execute_script("Object.assign(document.body.appendChild(document.createElement('form')), { method: 'post', action: '/dev/hackatime' }).submit()")
    end
    within_frame(goal) do
      assert_selector ".flash.notice", exact_text: "fake Hackatime linked"
      assert_selector "h2", text: "your meter"
    end
    within_frame(pet_frame) do
      assert_selector "h2", text: "edit rock"
      assert_no_selector ".flash"
    end
    assert_equal "window-goal.exe", front_window
  end

  test "a first visit, with nothing saved, opens welcome.txt" do
    forget_open_windows
    visit root_path
    assert_selector "#welcome"
    assert_no_selector "#window-goal\\.exe", visible: :all
  end

  test "the trash menu, open at the reload, opens again where it was" do
    visit root_path
    icon("trash").right_click
    # A fresh trash holds the banana peel.
    assert_selector "#trash-menu", text: "restore banana peel"
    at = page.evaluate_script("[document.getElementById('trash-menu').style.left, document.getElementById('trash-menu').style.top]")
    assert_saved "trash"
    visit root_path
    assert_selector "#trash-menu", text: "restore banana peel"
    assert_equal at, page.evaluate_script("[document.getElementById('trash-menu').style.left, document.getElementById('trash-menu').style.top]")
  end

  test "on a phone only the front window comes back" do
    resize_viewport_to(390, 844) do
      visit root_path
      press icon("guide.txt")
      press icon("rock")
      within_frame(pet_frame) { assert_selector "h2", text: "rock" }
      assert_saved "pet"
      visit root_path
      within_frame(pet_frame) { assert_selector "h2", text: "rock" }
      assert_no_selector "#welcome"
      assert_no_selector "#window-guide\\.txt"
      assert_no_selector "#window-goal\\.exe"
    end
  end

  test "with storage blocked, the desktop opens as on a first visit, and windows still open and close" do
    script = page.driver.browser.execute_cdp("Page.addScriptToEvaluateOnNewDocument", source: <<~JS)
      window.pageErrors = [];
      addEventListener("error", event => pageErrors.push(event.message));
      Object.defineProperty(window, "localStorage", { get() { throw new DOMException("blocked", "SecurityError"); } });
    JS
    visit root_path
    assert_selector "#welcome"
    press icon("guide.txt")
    press find("#window-guide\\.txt .windowclose")
    assert_no_selector "#window-guide\\.txt"
    visit root_path
    assert_selector "#welcome"
    assert_no_selector "#window-guide\\.txt"
    assert_empty page.evaluate_script("pageErrors")
  ensure
    page.driver.browser.execute_cdp("Page.removeScriptToEvaluateOnNewDocument", identifier: script["identifier"]) if script
  end

  private

  # Opens the pet's window on its edit page and its ship window, moves
  # welcome.txt, and puts the pet's window in front. A reload shows the same.
  def open_and_reload
    visit root_path
    press icon("rock")
    within_frame(pet_frame) { press find_link("ship") }
    within_frame(find("#window-ship-#{@rock.id} iframe")) { assert_text "ship rock" }
    within_frame(pet_frame) { press find_link("edit") }
    within_frame(pet_frame) { assert_selector "h2", text: "edit rock" }
    # Low and in the middle, clear of the required links at both sizes.
    page.execute_script("(win => Object.assign(win.style, { left: Math.round((innerWidth - win.offsetWidth) / 2) + 'px', top: innerHeight - win.offsetHeight - 60 + 'px' }))(document.getElementById('welcome'))")
    assert_equal "window-pet-#{@rock.id}", front_window
    before = settled_stack

    visit root_path
    within_frame(pet_frame) { assert_selector "h2", text: "edit rock" }
    page.document.synchronize do
      raise Capybara::ExpectationNotMet, "#{stack} is not #{before}" unless stack == before
    end
    assert_includes before.map(&:first), "window-ship-#{@rock.id}"
    assert_equal "window-pet-#{@rock.id}", front_window
  end

  def icon(label) = find(".app", exact_text: label)
  def goal = find(".ship-frame")
  def pet_window = "#window-pet-#{@rock.id}"
  def pet_frame = find("#{pet_window} iframe")

  # The open windows from the back to the front: each one's id, where it
  # sits, and the page in its frame.
  def stack
    page.evaluate_script(<<~JS)
      [...document.querySelectorAll(".window")].filter(w => getComputedStyle(w).display !== "none")
        .sort((a, b) => getComputedStyle(a).zIndex - getComputedStyle(b).zIndex)
        .map(w => [w.id, w.offsetLeft, w.offsetTop, w.querySelector("iframe")?.contentWindow.location.pathname ?? null])
    JS
  end

  # The stack once every window has been placed.
  def settled_stack
    page.document.synchronize do
      raise Capybara::ExpectationNotMet, "a window is still being placed" if page.evaluate_script("!!document.querySelector('.window[data-placing]')")
    end
    stack
  end

  def front_window = stack.last.first

  # Each open window's height, and its content's shown and whole heights and
  # scroll, by id.
  def sizes
    page.evaluate_script(<<~JS).to_h
      [...document.querySelectorAll(".window")].filter(w => getComputedStyle(w).display !== "none")
        .map(w => (content => [w.id, [w.offsetHeight, content.clientHeight, content.scrollHeight, content.scrollTop]])(w.querySelector(".windowcontent")))
    JS
  end

  def state_key = "playground-window-state:#{@user.id}"

  def saved_state
    JSON.parse(page.evaluate_script("localStorage.getItem(arguments[0])", state_key) || "[]")
  end

  # Written from a page that saves no windows, so the desktop cannot write
  # over it before the next visit.
  def save_state(state)
    visit dashboard_path
    page.execute_script("localStorage.setItem(arguments[0], arguments[1])", state_key, state.to_json)
  end

  # Enter on an icon, a link, or a button, which a window lying over it
  # cannot take.
  def press(element) = element.send_keys(:enter)

  # Whether the saved state names a window, or a page, soon.
  def assert_saved(text, present: true)
    page.document.synchronize do
      found = saved_state.to_json.include?(text)
      raise Capybara::ExpectationNotMet, "#{text} is #{"not " if present}saved: #{saved_state}" unless found == present
    end
  end
end
