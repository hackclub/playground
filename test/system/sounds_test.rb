require "application_system_test_case"

# The desktop's sounds: each word on the taskbar is a button that plays its
# own gulp, and the rock grumbles as it goes into the trash. A sound plays
# only on its press or drop. Audio is stubbed from before the page loads, so
# the test hears each play: its file and volume.
class SoundsTest < ApplicationSystemTestCase
  STUB = <<~JS.freeze
    window.plays = []
    window.Audio = class {
      constructor(src) { this.src = src; this.volume = 1; this.currentTime = 0 }
      play() { plays.push([this.src.split("/").pop().replace(/-[0-9a-f]+\\.mp3$/, ".mp3"), this.volume]); return Promise.resolve() }
    }
  JS

  teardown { page.driver.browser.execute_cdp("Page.removeScriptToEvaluateOnNewDocument", identifier: @script) if @script }

  test "each word on the taskbar is a button that plays its own gulp, again on each press" do
    before_each_page STUB
    visit root_path
    gulp, gulp2 = find("#bar button", exact_text: "gulp"), find("#bar button", exact_text: "gulp2")
    assert_equal [ "button", "button" ], [ gulp[:type], gulp2[:type] ]
    assert_equal [], plays, "nothing plays on load"

    gulp.click
    gulp2.click
    gulp.click
    assert_equal [ [ "gulp.mp3", 0.5 ], [ "gulp2.mp3", 0.5 ], [ "gulp.mp3", 0.5 ] ], plays

    # The keyboard reaches each word and plays it with Enter or Space.
    gulp2.send_keys(:enter)
    gulp.send_keys(:space)
    assert_equal [ [ "gulp2.mp3", 0.5 ], [ "gulp.mp3", 0.5 ] ], plays.last(2)
    assert_equal "gulp", page.evaluate_script("document.activeElement.textContent")
  end

  test "the rock grumbles as it goes into the trash, and not on a reload or a restore" do
    before_each_page STUB
    visit root_path
    # A press above the rock's foot, which stands behind the taskbar's top edge.
    rock = page.evaluate_script(<<~JS)
      (() => {
        const shown = ["desktop-pet", "desktop-pet-static"].map(id => document.getElementById(id)).find(el => getComputedStyle(el).display !== "none")
        const box = shown.getBoundingClientRect()
        return [box.left + box.width / 2, box.top + box.height * 0.55].map(Math.round)
      })()
    JS
    can = page.evaluate_script("(box => [box.left + box.width / 2, box.top + box.height / 2].map(Math.round))(document.querySelector('.app[data-key=trash]').getBoundingClientRect())")
    page.driver.browser.action.move_to_location(*rock).click_and_hold.move_to_location(rock[0] + 10, rock[1] - 10)
      .move_to_location(*can).release.perform
    assert_selector "#desktop-pet.in-trash", visible: :all
    assert_equal [ [ "rock-trashed.mp3", 0.5 ] ], plays

    visit root_path
    assert_selector "#desktop-pet.in-trash", visible: :all
    find(".app[data-key=trash]").click
    within("#trash-menu") { click_button "restore rock" }
    assert_selector "#desktop-pet.walking"
    assert_equal [], plays
  end

  test "a browser that cannot play audio stays quiet, with no errors" do
    before_each_page <<~JS
      delete window.Audio
      window.pageErrors = []
      addEventListener("error", event => pageErrors.push(event.message))
      addEventListener("unhandledrejection", event => pageErrors.push(String(event.reason)))
    JS
    visit root_path
    find("#bar button", exact_text: "gulp").click
    find("#bar button", exact_text: "gulp2").click
    assert_empty page.evaluate_script("pageErrors")
  end

  private
    # Runs a script in every page from now on, before the page's own.
    def before_each_page(script)
      @script = page.driver.browser.execute_cdp("Page.addScriptToEvaluateOnNewDocument", source: script)["identifier"]
    end

    def plays
      page.evaluate_script("plays")
    end
end
