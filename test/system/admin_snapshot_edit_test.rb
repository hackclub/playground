require "application_system_test_case"

# The admin ship page edits the ship's screenshots with the grid participants
# use: an upload lands on the end, the arrow keys move one, and × removes
# one. Each saves at once to the ship, and the pet keeps its own.
class AdminSnapshotEditSystemTest < ApplicationSystemTestCase
  # Stored screenshots load from this app, so the browser can draw them.
  class LocalStore < MemoryScreenshotStore
    def url(key) = "#{Capybara.current_session.server.base_url}/icon.png?#{key}"
  end

  setup do
    ScreenshotStore.current = LocalStore.new
    # The upload sends the page's CSRF token, which only renders with this on.
    ActionController::Base.allow_forgery_protection = true
    participant = User.create!(hca_id: "ident!snap-sys", verification_status: "verified", ysws_eligible: true)
    @project = participant.projects.create!(name: "rock")
    @urls = %w[a b].map { ScreenshotStore.current.url("saved-#{it}.webp") }
    @ship = @project.ships.create!(user: participant, claimed_seconds: 3600, snapshot: { "screenshots" => @urls, "screenshot_url" => @urls.first })
    @file = Tempfile.new([ "shot", ".png" ]).tap { it.binmode; it.write(image_bytes(1280, 720)); it.close }
    visit dev_login_path(as: "admin", admin: 1)
    assert_selector ".adminnav"
  end

  teardown do
    ActionController::Base.allow_forgery_protection = false
    @file.unlink
  end

  test "an upload, a move, and a removal each save to the ship" do
    visit admin_ship_path(@ship)
    find("#snapshot-edit summary").click
    find("#snapshot-edit input[type=file]", visible: :hidden).set(@file.path)
    assert_selector "#snapshot-edit .upload-status", text: "uploaded ✓"
    assert_equal 3, @ship.reload.snapshot["screenshots"].size
    added = @ship.snapshot["screenshots"].last

    find("#snapshot-edit .thumb[data-id='#{ShipSnapshot.shot_id(added)}']").send_keys(:left, :left)
    assert_selector "#snapshot-edit .upload-status", text: "moved to 1 of 3"
    assert_selector "#snapshot-edit .thumb.cover[data-id='#{ShipSnapshot.shot_id(added)}']"
    wait_for { @ship.reload.snapshot["screenshot_url"] == added }
    assert_equal [ added, *@urls ], @ship.snapshot["screenshots"]

    find("#snapshot-edit .thumb[data-id='#{ShipSnapshot.shot_id(@urls.first)}'] .remove").click
    assert_selector "#snapshot-edit .upload-status", text: "removed ✓"
    assert_equal [ added, @urls.last ], @ship.reload.snapshot["screenshots"]
    assert_empty @project.reload.screenshots, "the pet keeps its own"

    visit admin_ship_path(@ship)
    assert_selector "#snapshot-edited", text: /edited by .+ ago/
  end

  private

  def wait_for(seconds = 3)
    deadline = Time.current + seconds
    sleep 0.05 until yield || Time.current > deadline
  end
end
