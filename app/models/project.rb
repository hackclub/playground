# A desktop pet. It links any number of the participant's Hackatime projects,
# named however they like. Lapse syncs to Hackatime, so
# art time arrives the same way.
class Project < ApplicationRecord
  # A ship message is a post in #playground-ships (channel C0C51NCK1DG),
  # linked from Slack's "copy link": a thread reply adds a query.
  SHIP_MESSAGE_LINK = %r{\Ahttps://hackclub\.slack\.com/archives/C0C51NCK1DG/p\d+(\?\S*)?\z}

  belongs_to :user
  has_many :ships, -> { order(:created_at) }, dependent: :destroy

  validates :name, presence: true, length: { maximum: 80 }
  validates :description, length: { maximum: 2000 }
  validates :code_url, :playable_url,
            format: { with: %r{\Ahttps?://\S+\z}, message: "must be a full http(s) link" }, allow_blank: true
  validates :ship_message_url, format: { with: SHIP_MESSAGE_LINK, message: "must be a link to your message in #playground-ships" },
                               allow_blank: true
  validate :hackatime_projects_are_plain_names
  validate :hackatime_projects_are_unique_to_this_project
  validate :screenshots_are_a_short_list_of_links

  before_validation { self.hackatime_projects = Array(hackatime_projects).compact_blank.uniq }

  # When the pet's Hackatime projects change, the owner's coding hours are
  # fetched again from the program start: a newly linked project brings its
  # earlier time, and one no longer counted takes its time away.
  after_save :refetch_coding_hours, if: :saved_change_to_hackatime_projects?
  after_destroy :refetch_coding_hours
  # The owner's first pet time, kept when that pet is deleted, for the Loops
  # event. The owner's row syncs next.
  after_create { User.where(id: user_id, first_pet_created_at: nil).update_all(first_pet_created_at: created_at, synced_at: nil) }

  def latest_ship = ships.last
  def pending_ship? = ships.any?(&:pending?)
  def state = latest_ship&.state || "draft"

  # The pet's desktop icon: its name.
  def desktop_icon = { id:, name: }

  # Hours from the linked Hackatime projects not yet claimed by a ship.
  def unshipped_seconds(project_ships = ships)
    [ tracked_seconds - claimed_by(project_ships), 0 ].max
  end

  # tracked_seconds holds only time inside the program window, so a ship
  # taken before the window opened claimed none of it.
  def claimed_by(project_ships = ships)
    opened = ProgramWindow.current.starts_at
    project_ships.reject { it.changes_needed? || it.created_at < opened }.sum(&:claimed_seconds)
  end

  # The screenshots, in order, each { "id", "key", "url" }: the id names it
  # on the edit page, the key in storage. The first is the cover.
  def screenshot_urls = screenshots.map { it["url"] }
  def screenshot_url = screenshot_urls.first
  def screenshot(id) = screenshots.find { it["id"] == id }

  def github_repo
    repo = code_url.to_s[%r{\Ahttps://github\.com/([\w.-]+/[\w.-]+?)(?:\.git)?/?\z}, 1]
    repo unless repo.to_s.split("/").any? { it.match?(/\A\.+\z/) }
  end

  # How two Hackatime project names are compared. Hackatime's own matching
  # is not documented, so case and edge spaces don't tell names apart.
  def self.hackatime_key(name) = name.to_s.strip.downcase

  # Names this pet can't link: those the participant's other pets link now,
  # and those their ships claimed time from. A shipped name stays with its
  # pet after it is unlinked there, so its hours can't be claimed twice.
  def hackatime_projects_taken
    user.projects.where.not(id: id).includes(:ships).flat_map { it.hackatime_projects + it.shipped_hackatime_projects }
  end

  # Every Hackatime project a ship of this pet claimed time from. A ship
  # sent back for changes claimed nothing.
  def shipped_hackatime_projects
    ships.reject(&:changes_needed?).flat_map do
      Array(it.snapshot["hackatime_projects"]) + Array(it.snapshot["projects"].try(:keys))
    end.uniq
  end

  private

  def refetch_coding_hours = User.where(id: user_id).update_all(coding_hours_synced_at: nil)

  def screenshots_are_a_short_list_of_links
    errors.add(:screenshots, "hold at most #{ScreenshotLimits::PER_PET}") if screenshots.size > ScreenshotLimits::PER_PET
    return if screenshots.all? { it.is_a?(Hash) && it["id"].present? && it["url"].to_s.match?(%r{\Ahttps?://\S+\z}) }
    errors.add(:screenshots, "must each be a saved image")
  end

  # Hackatime takes several projects as one comma-separated filter, so a
  # name with a comma would link more than one project.
  def hackatime_projects_are_plain_names
    return if hackatime_projects.all? { it.is_a?(String) && it.length <= 200 && !it.include?(",") }
    errors.add(:hackatime_projects, "must each be one Hackatime project, with no commas")
  end

  def hackatime_projects_are_unique_to_this_project
    taken = hackatime_projects_taken.map { self.class.hackatime_key(it) }.to_set
    clash = hackatime_projects.select { taken.include?(self.class.hackatime_key(it)) }
    errors.add(:hackatime_projects, "already linked to another pet: #{clash.join(", ")}") if clash.any?
  end
end
