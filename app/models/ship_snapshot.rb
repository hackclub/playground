# What a ship was taken with, as reviewers and the Airtable copy see it. An
# admin can correct the pet's name, description, links, and screenshots here.
# Only the ship's snapshot changes: the participant's pet keeps its own.
#
# The name is written to the snapshot only once an admin edits it. Until then
# it is the pet's current name. Each edit records the admin and the time, and
# marks the ship for the next Airtable sync.
class ShipSnapshot
  include ActiveModel::Model
  include ActiveModel::Attributes

  TEXT = %w[name description code_url playable_url ship_message_url].freeze

  attribute :name, :string
  attribute :description, :string
  attribute :code_url, :string
  attribute :playable_url, :string
  attribute :ship_message_url, :string

  # The same rules as the participant's pet form.
  validates :name, presence: true, length: { maximum: 80 }
  validates :description, length: { maximum: 2000 }
  validates :code_url, :playable_url, format: { with: Project::LINK, message: "must be a full http(s) link" }, allow_blank: true
  validates :ship_message_url, format: { with: Project::SHIP_MESSAGE_LINK, message: "must be a link to a message in #playground-ships" },
                               allow_blank: true

  attr_reader :ship

  def initialize(ship)
    @ship = ship
    super(TEXT.index_with { send(:"stored_#{it}") })
  end

  def self.name_of(ship) = ship.snapshot["name"].presence || ship.project.name

  # Screenshots in order, the cover first. An older ship has only its cover.
  def self.screenshot_urls(ship)
    snap = ship.snapshot
    Array(snap["screenshots"]).presence || Array(snap["screenshot_url"].presence)
  end

  # A snapshot holds plain URLs, so a screenshot is named by a digest of its own.
  def self.shot_id(url) = Digest::SHA256.hexdigest(url.to_s).first(16)

  def screenshot_urls = self.class.screenshot_urls(ship)
  def screenshots = screenshot_urls.map { { "id" => self.class.shot_id(it), "url" => it } }
  def screenshot(id) = screenshot_urls.find { self.class.shot_id(it) == id }

  def edited_at = ship.snapshot["edited_at"]&.then { Time.zone.parse(it) }
  def edited_by = ship.snapshot["edited_by"]&.then { User.find_by(id: it) }

  # Saves the text fields that differ from what the ship shows now. False when
  # one is invalid; nil when nothing changed.
  def update(params, by:)
    before = attributes.dup
    assign_attributes(params.to_h.slice(*TEXT).transform_values { it.to_s.strip })
    return false unless valid?
    changed = TEXT.reject { attributes[it].to_s == before[it].to_s.strip }
    return nil if changed.empty?
    write(by:, action: "snapshot.edit", fields: changed) do |snap|
      changed.each { snap[it] = attributes[it].presence }
    end
  end

  # Replaces the screenshot list. The block gets the list and returns the new
  # one, or nil to leave it. Runs under the ship's row lock, so two admins'
  # edits don't lose each other's.
  def update_screenshots(by:, action:, **data)
    ship.with_lock do
      urls = yield(screenshot_urls.dup)
      next nil unless urls
      write(by:, action:, **data) do |snap|
        snap["screenshots"] = urls
        snap["screenshot_url"] = urls.first
      end
    end
  end

  private

  def stored_name = self.class.name_of(ship)
  def stored_description = ship.snapshot["description"]
  def stored_code_url = ship.snapshot["code_url"]
  def stored_playable_url = ship.snapshot["playable_url"]
  def stored_ship_message_url = ship.snapshot["ship_message_url"]

  # A new hash, so Active Record sees the jsonb change. A nil synced_at puts
  # the ship first in the next Airtable sync. The row lock reloads the ship
  # first, so only the fields given change.
  def write(by:, action:, **data)
    ship.with_lock do
      snap = ship.snapshot.deep_dup
      yield snap
      snap["edited_by"] = by.id
      snap["edited_at"] = Time.current.iso8601
      ship.update!(snapshot: snap, synced_at: nil)
      AuditEvent.record(by, ship, action, **data)
    end
    true
  end
end
