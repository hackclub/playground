require "test_helper"

# A pet's screenshots: each upload is checked, stored under a name the server
# picks, and added to the end of the pet's list, up to ScreenshotLimits::PER_PET.
# One can be replaced in place, removed, or moved, and the files that go are
# deleted unless a ship was reviewed with them.
class ScreenshotUploadTest < ActionDispatch::IntegrationTest
  setup do
    @user = log_in("participant")
    @project = @user.projects.create!(name: "rock")
  end

  test "an upload is processed, stored under a server-chosen name, and added to the pet's list" do
    upload_screenshot(@project)
    assert_response :created
    shot = @project.reload.screenshots.sole
    assert_match %r{\Atest/screenshots/#{@project.id}/#{shot["id"]}\.webp\z}, shot["key"]
    assert_match(/\A[0-9a-f-]{36}\z/, shot["id"])
    assert_equal "https://playground.hackclub-assets.com/#{shot["key"]}", shot["url"]
    assert_equal({ "id" => shot["id"], "url" => shot["url"] }, response.parsed_body.slice("id", "url"),
                 "the edit page loads the new image from this URL before it swaps it in")
    stored = ScreenshotStore.current.objects.fetch(shot["key"])
    assert_equal "WEBP", stored.byteslice(8, 4), "the stored bytes are our re-encode, not the upload"
  end

  test "uploads add to the end, the first is the cover, and the list stops at its limit" do
    ScreenshotLimits::PER_PET.times { upload_screenshot(@project) }
    shots = @project.reload.screenshots
    assert_equal ScreenshotLimits::PER_PET, shots.size
    assert_equal shots.first["url"], @project.screenshot_url
    assert_equal shots.pluck("url"), @project.screenshot_urls

    upload_screenshot(@project)
    assert_response :unprocessable_entity
    assert_equal "a pet holds up to 6 screenshots. remove one to add another.", response.parsed_body["error"]
    assert_equal shots, @project.reload.screenshots
    assert_equal ScreenshotLimits::PER_PET, ScreenshotStore.current.objects.size, "nothing past the limit is stored"
  end

  test "a rejected file is never stored" do
    upload_screenshot(@project, image_bytes(300, 200))
    assert_response :unprocessable_entity
    assert_match "640×360", response.parsed_body["error"]
    assert_empty ScreenshotStore.current.objects
    assert_empty @project.reload.screenshots
  end

  test "a lying Content-Type does not help" do
    upload_screenshot(@project, "<svg xmlns='http://www.w3.org/2000/svg'/>", "image/png")
    assert_response :unprocessable_entity
    assert_empty ScreenshotStore.current.objects
  end

  test "an oversized request is refused before the body is read" do
    post project_screenshots_path(@project), headers: { "Accept" => "application/json", "CONTENT_LENGTH" => (9 * 1024 * 1024).to_s }
    assert_response :content_too_large
  end

  test "someone else's project cannot be written, reordered, or emptied" do
    other = User.create!(hca_id: "ident!other").projects.create!(name: "not yours",
      screenshots: [ { "id" => "theirs", "key" => "theirs.webp", "url" => "https://playground.hackclub-assets.com/theirs.webp" } ])
    upload_screenshot(other)
    assert_response :not_found
    delete project_screenshot_path(other, "theirs"), headers: { "Accept" => "application/json" }
    assert_response :not_found
    patch order_project_screenshots_path(other), params: { ids: [ "theirs" ] }, as: :json
    assert_response :not_found
    assert_equal [ "theirs" ], other.reload.screenshots.pluck("id")
    assert_empty ScreenshotStore.current.deleted
  end

  test "logged out uploads go nowhere" do
    reset!
    upload_screenshot(@project)
    assert_response :unauthorized
    assert_empty ScreenshotStore.current.objects
  end

  test "replacing one keeps its place and deletes its file, unless a ship was reviewed with it" do
    3.times { upload_screenshot(@project) }
    first, second, third = @project.reload.screenshots
    upload_screenshot(@project, replace: second["id"])
    assert_response :created
    now = @project.reload.screenshots
    assert_equal [ first, third ], [ now[0], now[2] ]
    assert_equal response.parsed_body["id"], now[1]["id"]
    assert_includes ScreenshotStore.current.deleted, second["key"]

    @project.ships.create!(user: @user, snapshot: { "screenshot_url" => first["url"], "screenshots" => now.pluck("url") })
    upload_screenshot(@project, replace: now[1]["id"])
    refute_includes ScreenshotStore.current.deleted, now[1]["key"], "the ship's list keeps it"
    upload_screenshot(@project, replace: first["id"])
    refute_includes ScreenshotStore.current.deleted, first["key"], "the ship's cover keeps it"

    upload_screenshot(@project, replace: "gone")
    assert_response :not_found
    assert_equal 3, @project.reload.screenshots.size
  end

  test "removing one deletes its file, unless a ship was reviewed with it, and the last may go" do
    2.times { upload_screenshot(@project) }
    first, second = @project.reload.screenshots
    @project.ships.create!(user: @user, snapshot: { "screenshot_url" => first["url"] })

    delete project_screenshot_path(@project, second["id"]), headers: { "Accept" => "application/json" }
    assert_response :no_content
    assert_includes ScreenshotStore.current.deleted, second["key"]
    delete project_screenshot_path(@project, first["id"]), headers: { "Accept" => "application/json" }
    assert_response :no_content
    refute_includes ScreenshotStore.current.deleted, first["key"]
    assert_empty @project.reload.screenshots
    assert_nil @project.screenshot_url

    delete project_screenshot_path(@project, first["id"]), headers: { "Accept" => "application/json" }
    assert_response :not_found
  end

  test "a new order is saved only when it holds exactly the pet's screenshots" do
    3.times { upload_screenshot(@project) }
    ids = @project.reload.screenshots.pluck("id")
    patch order_project_screenshots_path(@project), params: { ids: ids.reverse }, as: :json
    assert_response :no_content
    assert_equal ids.reverse, @project.reload.screenshots.pluck("id")
    assert_equal @project.screenshots.first["url"], @project.screenshot_url, "the new first is the cover"

    [ ids.first(2), ids + [ "other" ], [ ids[0], ids[0], ids[1] ] ].each do |wrong|
      patch order_project_screenshots_path(@project), params: { ids: wrong }, as: :json
      assert_response :conflict
    end
    assert_equal ids.reverse, @project.reload.screenshots.pluck("id")
    assert_empty ScreenshotStore.current.deleted, "a move deletes nothing"
  end

  test "with no R2 keys, uploads refuse and nothing is saved anywhere" do
    unconfigured = ScreenshotStore.new
    unconfigured.define_singleton_method(:configured?) { false }
    ScreenshotStore.current = unconfigured
    upload_screenshot(@project)
    assert_response :service_unavailable
    assert_match "isn't set up", response.parsed_body["error"]
    assert_empty @project.reload.screenshots
  end
end
