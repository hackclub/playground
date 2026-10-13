require "test_helper"

# An admin corrects a ship's snapshot from the ship page: the pet's name,
# description, links, and screenshots. Only the ship changes. Each edit
# records who and when, and marks the ship for the next Airtable sync.
class AdminSnapshotEditTest < ActionDispatch::IntegrationTest
  LIVE = "https://playground.hackclub-assets.com/test/screenshots/live.webp".freeze
  OLD = "https://playground.hackclub-assets.com/test/screenshots/old.webp".freeze

  setup do
    @participant = User.create!(hca_id: "ident!snap-#{SecureRandom.hex(3)}", verification_status: "verified", ysws_eligible: true)
    @project = @participant.projects.create!(name: "rock", description: "a rock", code_url: "https://github.com/pet/rock",
                                             screenshots: [ { "id" => "live", "key" => "test/screenshots/live.webp", "url" => LIVE } ])
    @ship = @project.ships.create!(user: @participant, claimed_seconds: 3600, state: "approved", review_status: "approved",
                                   fraud_status: "passed", approved_seconds: 3600,
                                   snapshot: { "code_url" => "https://github.com/pet/rock", "description" => "a rock",
                                               "screenshots" => [ LIVE, OLD ], "screenshot_url" => LIVE })
    @ship.update_column(:synced_at, 1.minute.ago)
    @admin = log_in("admin")
    @admin.update_column(:display_name, "careful heron")
  end

  def edit(fields) = patch(snapshot_admin_ship_path(@ship, stage: "review"), params: { snapshot: fields })

  test "the fields save to the ship, not the pet, and the edit is recorded and synced again" do
    edit(name: "pebble", description: "a small rock", code_url: "https://github.com/pet/pebble",
         playable_url: "https://pebble.example", ship_message_url: "https://hackclub.slack.com/archives/C0C51NCK1DG/p1712345678")
    assert_redirected_to admin_ship_path(@ship, stage: "review")
    snap = @ship.reload.snapshot
    assert_equal [ "pebble", "a small rock", "https://github.com/pet/pebble", "https://pebble.example" ],
                 snap.values_at("name", "description", "code_url", "playable_url")
    assert_equal @admin.id, snap["edited_by"]
    assert_nil @ship.synced_at, "the ship goes first in the next Airtable sync"
    assert_equal [ "rock", "a rock", "https://github.com/pet/rock" ], @project.reload.slice(:name, :description, :code_url).values
    assert_equal "snapshot.edit", AuditEvent.where(subject: @ship).last.action

    fields = AirtableFields.ship(@ship)
    assert_equal [ "https://github.com/pet/pebble", "https://pebble.example", "a small rock" ], fields.values_at("Code URL", "Playable URL", "Description")

    follow_redirect!
    assert_select "h1", /\Apebble/
    assert_select "#snapshot-edited", /edited by careful heron less than a minute ago/
  end

  test "only the fields that changed are written, so the name follows the pet until an admin sets it" do
    edit(name: "rock", description: "a rock", code_url: "https://github.com/pet/rock")
    assert_equal "nothing changed", flash[:notice]
    assert_not @ship.reload.snapshot.key?("edited_at")
    assert @ship.synced_at

    edit(name: "rock", description: "a better rock", code_url: "https://github.com/pet/rock")
    assert_not @ship.reload.snapshot.key?("name")
    @project.update!(name: "boulder")
    get admin_ship_path(@ship)
    assert_select "h1", /\Aboulder/
  end

  test "a bad link is refused like the pet form refuses it, and what was typed stays" do
    edit(name: "pebble", code_url: "github.com/pet/pebble", ship_message_url: "https://example.com/msg")
    assert_response :unprocessable_entity
    assert_select "details#snapshot-edit[open] .banner.alert", /must be a full http\(s\) link/
    assert_select "details#snapshot-edit .banner.alert", /#playground-ships/
    assert_select "input[name='snapshot[code_url]'][value='github.com/pet/pebble']"
    assert_not @ship.reload.snapshot.key?("name")

    edit(name: " ")
    assert_response :unprocessable_entity
  end

  test "the person page shows the edited name" do
    edit(name: "pebble")
    get admin_person_path(@participant)
    assert_match "pebble #1", response.body
  end

  test "an admin can't edit their own ship" do
    own = @admin.projects.create!(name: "mine").ships.create!(user: @admin, claimed_seconds: 60, snapshot: { "screenshots" => [ OLD ] })
    patch snapshot_admin_ship_path(own), params: { snapshot: { name: "better" } }
    assert_not own.reload.snapshot.key?("name")
    delete admin_ship_screenshot_path(own, ShipSnapshot.shot_id(OLD)), headers: { "Accept" => "application/json" }
    assert_response :forbidden
    assert_equal [ OLD ], own.reload.snapshot["screenshots"]
  end

  test "a participant can't reach the edits" do
    log_in("participant")
    patch snapshot_admin_ship_path(@ship), params: { snapshot: { name: "mine now" } }
    assert_not @ship.reload.snapshot.key?("name")
  end

  test "an upload goes to storage under the pet, and onto the end of the ship only" do
    post admin_ship_screenshots_path(@ship), params: { screenshot: upload }, headers: { "Accept" => "application/json" }
    assert_response :created
    url = response.parsed_body["url"]
    assert_match %r{\Ahttps://playground.hackclub-assets.com/test/screenshots/#{@project.id}/[0-9a-f-]{36}\.webp\z}, url
    assert_equal ShipSnapshot.shot_id(url), response.parsed_body["id"]
    assert_equal [ LIVE, OLD, url ], @ship.reload.snapshot["screenshots"]
    assert_equal [ LIVE ], @project.reload.screenshot_urls
    assert_nil @ship.synced_at
    assert_equal @admin.id, @ship.snapshot["edited_by"]
  end

  test "a rejected upload is never stored, and a full ship takes no more" do
    post admin_ship_screenshots_path(@ship), params: { screenshot: upload(image_bytes(300, 200)) }, headers: { "Accept" => "application/json" }
    assert_response :unprocessable_entity
    assert_empty ScreenshotStore.current.objects

    @ship.update!(snapshot: @ship.snapshot.merge("screenshots" => Array.new(ScreenshotLimits::PER_PET) { "https://x.example/#{it}.webp" }))
    post admin_ship_screenshots_path(@ship), params: { screenshot: upload }, headers: { "Accept" => "application/json" }
    assert_response :unprocessable_entity
    assert_match "up to 6", response.parsed_body["error"]
    assert_empty ScreenshotStore.current.objects
  end

  test "reorder picks the cover, and a stale order is refused" do
    patch order_admin_ship_screenshots_path(@ship), params: { ids: [ OLD, LIVE ].map { ShipSnapshot.shot_id(it) } }, as: :json
    assert_response :no_content
    assert_equal [ OLD, LIVE ], @ship.reload.snapshot["screenshots"]
    assert_equal OLD, @ship.snapshot["screenshot_url"]
    assert_equal [ { "url" => OLD } ], AirtableFields.ship(@ship)["Screenshot"]

    patch order_admin_ship_screenshots_path(@ship), params: { ids: [ ShipSnapshot.shot_id(LIVE) ] }, as: :json
    assert_response :conflict
  end

  test "removing keeps the file the pet still uses, and deletes one nothing shows" do
    delete admin_ship_screenshot_path(@ship, ShipSnapshot.shot_id(LIVE)), headers: { "Accept" => "application/json" }
    assert_response :no_content
    assert_equal [ OLD ], @ship.reload.snapshot["screenshots"]
    assert_equal OLD, @ship.snapshot["screenshot_url"], "the next one becomes the cover"
    assert_empty ScreenshotStore.current.deleted, "the pet still shows it"

    delete admin_ship_screenshot_path(@ship, ShipSnapshot.shot_id(OLD)), headers: { "Accept" => "application/json" }
    assert_equal [ "test/screenshots/old.webp" ], ScreenshotStore.current.deleted
    assert_empty @ship.reload.snapshot["screenshots"]

    delete admin_ship_screenshot_path(@ship, ShipSnapshot.shot_id(OLD)), headers: { "Accept" => "application/json" }
    assert_response :not_found
  end

  test "a replaced screenshot takes the old one's place" do
    post admin_ship_screenshots_path(@ship), params: { screenshot: upload, replace: ShipSnapshot.shot_id(OLD) },
                                             headers: { "Accept" => "application/json" }
    assert_response :created
    assert_equal [ LIVE, response.parsed_body["url"] ], @ship.reload.snapshot["screenshots"]
    assert_equal [ "test/screenshots/old.webp" ], ScreenshotStore.current.deleted
  end

  test "an older ship with only its cover gets a list once edited" do
    @ship.update!(snapshot: { "screenshot_url" => OLD })
    get admin_ship_path(@ship)
    assert_select "#snapshot-edit li.thumb[data-id=?] img[src=?]", ShipSnapshot.shot_id(OLD), OLD
    post admin_ship_screenshots_path(@ship), params: { screenshot: upload }, headers: { "Accept" => "application/json" }
    assert_equal [ OLD, response.parsed_body["url"] ], @ship.reload.snapshot["screenshots"]
  end

  private

  def upload(bytes = image_bytes(1280, 720))
    Rack::Test::UploadedFile.new(StringIO.new(bytes), "image/png", true, original_filename: "shot.png")
  end
end
