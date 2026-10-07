require "application_system_test_case"

# The guide's Ship it step in a real browser: the pet's ship list loads into
# the step, a field saves when it loses focus and its mark clears in place, a
# screenshot uploads and clears its mark, and a ready pet ships. The reader
# never leaves the guide.
class NewSiteGuideShipSystemTest < ApplicationSystemTestCase
  include NewSiteTests
  # Stored screenshots load from this app, so the browser can draw them.
  class LocalStore < MemoryScreenshotStore
    def url(key) = "#{Capybara.current_session.server.base_url}/icon.png?#{key}"
  end

  READY = { description: "a rock that walks along your taskbar", code_url: "https://github.com/pet/rock",
            ship_message_url: "https://hackclub.slack.com/archives/C0C51NCK1DG/p1759012345678901", playable_url: "https://pet.itch.io/rock",
            screenshots: [ { "id" => "shot", "key" => "shot.webp", "url" => "https://playground.hackclub-assets.com/shot.webp" } ] }.freeze

  setup do
    ScreenshotStore.current = LocalStore.new
    # The saves and the upload send the page's CSRF token, which only renders with this on.
    ActionController::Base.allow_forgery_protection = true
  end

  teardown do
    ActionController::Base.allow_forgery_protection = false
    @shot&.unlink
  end

  test "a field saves in the guide and its mark clears in place, and so does a screenshot upload" do
    pet = sign_in_with_pet("newbie")
    visit "/guide/publish#ship"
    assert_selector "#ship-step #ship-check-description.todo textarea"
    assert_no_selector ".requirements-note"
    find("#ship-check-description textarea").fill_in(with: READY[:description])
    find("#ship-check-code_url input").click
    assert_selector "#ship-check-description.ok"
    assert_equal READY[:description], pet.reload.description
    assert_equal "/guide/publish", page.evaluate_script("location.pathname")

    @shot = Tempfile.new([ "shot", ".png" ]).tap { it.binmode; it.write(image_bytes(1280, 720)); it.close }
    find("#ship-screenshot input[type=file]", visible: :hidden).set(@shot.path)
    assert_selector "#ship-check-screenshot.ok"
    assert_selector "#ship-screenshot .thumb", count: 1
    assert_equal 1, pet.reload.screenshots.size
    assert_equal "/guide/publish", page.evaluate_script("location.pathname")
    assert_no_selector ".requirements-note"
  end

  test "a ready pet ships from the guide, which then shows it in review" do
    pet = sign_in_with_pet("participant", **READY)
    visit "/guide/publish#ship"
    button = find("#ship-checks button", text: /\Aship \d/)
    page.execute_script("document.documentElement.dataset.stillHere = ''")
    accept_confirm { button.click }
    assert_selector "#ship-step .guide-do-title", text: "rock is in review"
    assert_equal "/guide/publish#ship", page.evaluate_script("location.pathname + location.hash")
    assert page.evaluate_script("'stillHere' in document.documentElement.dataset"), "the step turned in place, with no new page"
    assert pet.reload.pending_ship?
    # The next step beside the guide asks again and follows the pet into its
    # review. The card hides while its part of the guide is on screen.
    assert_selector "#hub-next #next-title", visible: :all, exact_text: "rock is in review"
  end

  # In ship.exe's popup the ship button sticks to the bottom of the list,
  # which scrolls. On a page it comes after the last step, and never sticks
  # to the bottom of the window over the steps.
  test "the ship button comes after the last step, on the ship page and in the guide, wide and narrow" do
    pet = sign_in_with_pet("newbie")
    [ [ 1440, 900 ], [ 390, 844 ] ].each do |width, height|
      resize_viewport_to(width, height) do
        visit ship_project_path(pet)
        assert_ship_button_last "the ship page at #{width}px"
        visit "/guide/publish#ship"
        assert_ship_button_last "the guide's Ship it step at #{width}px"
      end
    end
  end

  private

  # The list starts halfway down the window, so it runs past the bottom edge.
  def assert_ship_button_last(message)
    assert_selector "#ship-checks .checks > li", minimum: 4
    page.execute_script("document.getElementById('ship-checks').scrollIntoView(); window.scrollBy(0, -Math.round(innerHeight / 2))")
    last_bottom, row_top = page.evaluate_script(<<~JS)
      (() => {
        const list = document.getElementById("ship-checks")
        const steps = list.querySelectorAll(".checks > li")
        return [ steps[steps.length - 1].getBoundingClientRect().bottom, list.querySelector(":scope > .row").getBoundingClientRect().top ]
      })()
    JS
    assert_operator row_top, :>=, last_bottom, message
  end

  def sign_in_with_pet(kind, **fields)
    visit dev_login_path(as: kind)
    assert_selector "#guide"
    User.find_by!(hca_id: "ident!dev-#{kind}").projects.create!(name: "rock", hackatime_projects: [ "rock-pet" ], **fields)
  end
end
