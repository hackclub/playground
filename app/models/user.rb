# One Hack Club Auth identity. Anyone may sign up; submitting and redeeming
# need a verified, YSWS eligible identity.
class User < ApplicationRecord
  encrypts :hca_access_token, :hca_refresh_token, :hackatime_access_token

  has_many :projects, dependent: :destroy
  has_many :ships, dependent: :destroy
  has_many :redemptions, dependent: :destroy
  has_many :coding_hours, dependent: :delete_all

  scope :admins, -> { where(admin: true) }

  # Organizers are admins by email, from ADMIN_EMAILS (comma separated). An
  # email leaving the list ends admin at once. Without a list, as in
  # development, the stored flag decides.
  def self.admin_emails = ENV["ADMIN_EMAILS"].to_s.downcase.split(",").map(&:strip).compact_blank
  def admin_email? = self.class.admin_emails.include?(email.to_s.downcase)
  def acts_as_admin? = admin? && (self.class.admin_emails.empty? || admin_email?)

  # Rows whose copy in Airtable is stale go first. See Airtable::SyncJob.
  after_update :mark_unsynced, if: -> { (saved_changes.keys & SYNCED_FIELDS).any? }
  SYNCED_FIELDS = %w[email first_name last_name slack_id verification_status ysws_eligible banned_at].freeze

  # The banana peel is in a participant's desktop trash unless they took it
  # out themselves, which banana_peel_out records. A trash saved without it,
  # before it came, holds it still. The rest of the trash is as saved.
  BANANA_PEEL = "banana peel".freeze
  def desktop_trash_with_peel
    banana_peel_out? || desktop_trash.include?(BANANA_PEEL) ? desktop_trash : [ BANANA_PEEL, *desktop_trash ]
  end

  # Full name: only for shipping and the people page. Everywhere else shows
  # display_name.
  def full_name = [ first_name, last_name ].compact_blank.join(" ").presence || "unknown"

  def display_name
    read_attribute(:display_name).presence || DisplayName.assign(self).then { save if persisted?; read_attribute(:display_name) }
  end
  def verified? = verification_status == "verified"
  def eligible? = verified? && ysws_eligible
  def banned? = banned_at.present?
  def hackatime_connected? = hackatime_access_token.present?
  # Set for the current request when Hackatime refused the stored token. Not saved.
  attr_accessor :hackatime_unlinked
  def hackatime_red? = hackatime_trust_level == "red"

  # Copies the fields Hack Club Auth returns under raw_info["identity"]. The
  # payload drops false values, so a missing ysws_eligible means not eligible.
  def assign_identity(identity)
    self.email = identity["primary_email"] if identity["primary_email"]
    self.first_name = identity["first_name"] if identity.key?("first_name")
    self.last_name = identity["last_name"] if identity.key?("last_name")
    self.slack_id = identity["slack_id"] if identity.key?("slack_id")
    self.verification_status = identity["verification_status"]
    self.ysws_eligible = identity["ysws_eligible"] == true
    self.birthday = identity["birthday"] if identity["birthday"].present?
  end

  def hours = Hours.new(self)

  def ban!(reason, by:)
    update!(banned_at: Time.current, ban_reason: reason)
    AuditEvent.record(by, self, "ban", reason: reason)
  end

  private

  def mark_unsynced = update_column(:synced_at, nil)
end
