require "application_system_test_case"

# A pet's screenshots show one at a time on its page, on its own and in the
# pet's window: a round arrow at each side and a dot for each, on the image,
# by mouse or finger, the arrow keys once the carousel has focus, and a swipe
# on touch. Each arrow takes clicks down a strip of the image's side. The one
# showing is announced. A pet with one screenshot shows it alone.
class ScreenshotCarouselTest < ApplicationSystemTestCase
  setup do
    @user = log_in_as("participant")
    @pet = @user.projects.create!(name: "rock", description: "naps on your windows")
  end

  teardown do
    page.driver.browser.execute_cdp("Emulation.setTouchEmulationEnabled", enabled: false)
    page.driver.browser.execute_cdp("Emulation.clearDeviceMetricsOverride")
  end

  test "arrows and dots step and wrap around, the keys step once it has focus, and each step is announced" do
    screenshots 3
    visit project_path(@pet)
    assert_selector "h2", exact_text: "screenshots"
    within ".carousel[role=region][aria-roledescription=carousel][aria-label='screenshots of rock']" do
      assert_showing 1
      assert_selector "img.shot", count: 3, visible: :all
      click_button "next screenshot", enable_aria_label: true
      assert_showing 2
      assert_selector "[aria-live=polite]", text: "screenshot 2 of 3", visible: :all
      click_button "screenshot 3", enable_aria_label: true
      assert_showing 3
      click_button "next screenshot", enable_aria_label: true
      assert_showing 1, "next wraps to the first"
      click_button "previous screenshot", enable_aria_label: true
      assert_showing 3, "previous wraps to the last"
    end

    carousel = find(".carousel")
    carousel.send_keys(:left)
    assert_showing 2
    carousel.send_keys(:home)
    assert_showing 1
    carousel.send_keys(:end)
    assert_showing 3
    carousel.send_keys(:right)
    assert_showing 1
    assert_selector "[aria-live=polite]", text: "screenshot 1 of 3", visible: :all
  end

  test "each arrow takes clicks down a strip a fifth of the screenshot wide, and its knob brightens and takes the focus" do
    screenshots 3
    visit project_path(@pet)
    shot = box(".carousel .shot:not([aria-hidden])")
    strip = box(".side.next")
    assert_equal [ shot["top"], shot["height"] ], [ strip["top"], strip["height"] ], "the strip runs down the whole side"
    assert_in_delta [ 44, shot["width"] / 5 ].max, strip["width"], 1
    assert_in_delta shot["right"], strip["right"], 1
    assert_equal "pointer", page.evaluate_script("getComputedStyle(document.querySelector('.side.next')).cursor")

    # Near the strip's top, well away from its knob, still steps.
    corner = find(".side.previous")
    page.driver.browser.action.move_to(corner.native, 0, -(strip["height"] / 2 - 6).round).click.perform
    assert_showing 3
    knob = "getComputedStyle(document.querySelector('.side.previous .knob')).backgroundColor"
    assert_equal "rgb(255, 255, 255)", page.evaluate_script(knob), "the pointer on the strip brightens its knob"
    page.driver.browser.action.move_to(find("h2", text: "screenshots").native).perform
    assert_equal "rgba(255, 255, 255, 0.8)", page.evaluate_script(knob)

    find(".carousel").send_keys(:tab)
    assert_equal "previous screenshot", page.evaluate_script("document.activeElement.getAttribute('aria-label')")
    assert_equal "solid", page.evaluate_script("getComputedStyle(document.querySelector('.side.previous .knob')).outlineStyle")
  end

  test "with screenshots of every shape, the carousel keeps one size, centres each, and keeps its arrows and dots on it" do
    shapes = [ [ 1280, 720 ], [ 900, 1200 ], [ 2560, 640 ], [ 1000, 1000 ] ]
    @pet.update_columns(screenshots: shapes.each_with_index.map { |(width, height), n|
      { "id" => "shot-#{n}", "key" => "shot-#{n}.png", "url" => "data:image/png;base64,#{Base64.strict_encode64(image_bytes(width, height))}" }
    })
    [ [ 1440, 900 ], [ 390, 844 ] ].each do |size|
      resize_viewport_to(*size) do
        visit project_path(@pet)
        page.document.synchronize { raise Capybara::ExpectationNotMet, "images loading" unless page.evaluate_script("[...document.querySelectorAll('.carousel .shot')].every((img) => img.complete && img.naturalWidth)") }
        first = nil
        shapes.each_with_index do |shape, index|
          assert_showing index + 1
          box, shot = box(".carousel .slides"), box(".carousel .shot:not([aria-hidden])")
          first ||= box
          assert_equal first.values_at("left", "top", "width", "height"), box.values_at("left", "top", "width", "height"), "the carousel holds still at #{size} on #{shape}"
          assert_in_delta box["left"] + box["width"] / 2, shot["left"] + shot["width"] / 2, 1, "#{shape} centred across at #{size}"
          assert_in_delta box["top"] + box["height"] / 2, shot["top"] + shot["height"] / 2, 1, "#{shape} centred down at #{size}"
          [ ".side.previous .knob", ".side.next .knob", ".carousel .dots" ].each do |part|
            on = box(part)
            assert on["left"] >= shot["left"] && on["right"] <= shot["right"] && on["top"] >= shot["top"] && on["bottom"] <= shot["bottom"],
                   "#{part} sits on the #{shape} screenshot at #{size}: #{on.slice("left", "top", "right", "bottom")} in #{shot.slice("left", "top", "right", "bottom")}"
          end
          find(".side.next").click
        end
      end
    end
  end

  test "the dots sit on the screenshot near its bottom, the current one blue and the others grey" do
    screenshots 3
    visit project_path(@pet)
    click_button "next screenshot", enable_aria_label: true
    shot = box(".carousel .shot:not([aria-hidden])")
    dots = box(".carousel .dots")
    assert_operator dots["left"], :>=, shot["left"]
    assert_operator dots["right"], :<=, shot["right"]
    assert_in_delta shot["left"] + shot["width"] / 2, dots["left"] + dots["width"] / 2, 1, "centred"
    assert_operator shot["bottom"] - dots["bottom"], :<=, 20, "near the bottom edge"
    assert_operator dots["bottom"], :<, shot["bottom"], "on the image"
    colours = page.evaluate_script("[...document.querySelectorAll('.carousel .dot')].map((dot) => getComputedStyle(dot, '::before').backgroundColor)")
    assert_equal [ "rgb(107, 122, 140)", "rgb(58, 112, 184)", "rgb(107, 122, 140)" ], colours
  end

  test "a finger swiped sideways steps, and one moved up or down does not" do
    screenshots 2
    visit project_path(@pet)
    assert_showing 1
    x, y = center(".carousel .slides")
    swipe from: [ x + 60, y ], to: [ x - 60, y + 4 ]
    assert_showing 2
    swipe from: [ x - 60, y ], to: [ x + 60, y - 4 ]
    assert_showing 1
    swipe from: [ x, y + 30 ], to: [ x + 8, y - 60 ]
    assert_showing 1

    # A swipe across an arrow's strip steps once, not again for the strip.
    strip = box(".side.next")
    swipe from: [ strip["right"] - 8, y ], to: [ strip["right"] - 60, y ]
    assert_showing 2
  end

  test "one screenshot shows alone, with nothing to step through" do
    screenshots 1
    visit project_path(@pet)
    assert_selector "h2", exact_text: "screenshot"
    assert_selector "img.shot[alt='screenshot of rock']"
    assert_no_selector ".carousel, .side, .dot"
  end

  test "in the pet's window on a phone, the carousel fits the window and steps by arrow and swipe" do
    screenshots 3
    resize_viewport_to(390, 844) do
      visit root_path
      find(".app[data-key='pet-#{@pet.id}']").send_keys(:enter)
      frame = find("#window-pet-#{@pet.id} iframe")
      within_frame(frame) do
        assert_showing 1
        fits = page.evaluate_script("document.querySelector('.carousel').getBoundingClientRect().right <= document.documentElement.clientWidth")
        assert fits, "the carousel fits the window"
        click_button "next screenshot", enable_aria_label: true
        assert_showing 2
      end
      box = page.evaluate_script("arguments[0].getBoundingClientRect().toJSON()", frame)
      x, y = within_frame(frame) { center(".carousel .slides") }
      swipe from: [ box["left"] + x + 50, box["top"] + y ], to: [ box["left"] + x - 50, box["top"] + y ]
      within_frame(frame) { assert_showing 3 }
    end
  end

  private

  # Stored screenshots load from this app, so the browser can draw them.
  def screenshots(count)
    base = Capybara.current_session.server.base_url
    @pet.update!(screenshots: Array.new(count) { |n| { "id" => "shot-#{n}", "key" => "shot-#{n}.png", "url" => "#{base}/icon.png?shot-#{n}" } })
  end

  def assert_showing(number, message = nil)
    assert_selector ".carousel img.shot:not([aria-hidden])", count: 1, visible: :all
    assert_selector ".carousel img.shot:not([aria-hidden])[alt^='screenshot #{number} of ']", visible: :all
    assert has_selector?(".dot[aria-current=true][aria-label='screenshot #{number}']"), message || "screenshot #{number} shows"
  end

  def box(selector) = page.evaluate_script("document.querySelector(arguments[0]).getBoundingClientRect().toJSON()", selector)

  def center(selector)
    box = page.evaluate_script("document.querySelector(arguments[0]).getBoundingClientRect().toJSON()", selector)
    [ (box["left"] + box["width"] / 2).round, (box["top"] + box["height"] / 2).round ]
  end

  def swipe(from:, to:)
    browser = page.driver.browser
    browser.execute_cdp("Emulation.setTouchEmulationEnabled", enabled: true, maxTouchPoints: 1)
    browser.execute_cdp("Input.dispatchTouchEvent", type: "touchStart", touchPoints: [ { x: from[0], y: from[1] } ])
    halfway = from.zip(to).map { |a, b| (a + b) / 2 }
    browser.execute_cdp("Input.dispatchTouchEvent", type: "touchMove", touchPoints: [ { x: halfway[0], y: halfway[1] } ])
    browser.execute_cdp("Input.dispatchTouchEvent", type: "touchMove", touchPoints: [ { x: to[0], y: to[1] } ])
    browser.execute_cdp("Input.dispatchTouchEvent", type: "touchEnd", touchPoints: [])
  end
end
