# A goal a participant redeemed. Every goal goes through the fulfillment queue.
# The address is frozen from Hack Club Auth at redeem time and encrypted;
# every reveal is logged.
class Redemption < ApplicationRecord
  STATUSES = %w[pending on_hold fulfilled rejected].freeze

  belongs_to :user
  belongs_to :fulfilled_by, class_name: "User", optional: true
  has_many :claims, as: :claimable, dependent: :delete_all

  encrypts :address
  serialize :address, coder: JSON

  validates :status, inclusion: { in: STATUSES }
  validates :goal_key, inclusion: { in: -> { Goal.all.map(&:key) } }, uniqueness: { scope: :user_id }
  validates :address, presence: true

  scope :to_fulfill, -> { where(status: "pending").order(:created_at) }

  after_update :mark_unsynced, if: :saved_change_to_status?

  def goal = Goal.find(goal_key)

  def hang_days = ((Time.current - created_at) / 1.day).floor

  def reveal_address!(by:)
    AuditEvent.record(by, self, "address.reveal")
    address
  end

  def fulfill!(by:, tracking:, cost_cents: nil, notes: nil)
    update!(status: "fulfilled", fulfilled_by: by, fulfilled_at: Time.current, tracking: tracking.presence,
            cost_cents: cost_cents, notes: notes.presence || self.notes)
    AuditEvent.record(by, self, "fulfillment.fulfill", tracking: tracking)
  end

  def hold!(by:, notes:)
    update!(status: "on_hold", notes: notes)
    AuditEvent.record(by, self, "fulfillment.hold")
  end

  def release!(by:)
    update!(status: "pending")
    AuditEvent.record(by, self, "fulfillment.release")
  end

  def reject!(by:, notes:)
    raise ArgumentError, "give a reason" if notes.blank?
    update!(status: "rejected", notes: notes)
    AuditEvent.record(by, self, "fulfillment.reject")
  end

  private

  def mark_unsynced = update_column(:synced_at, nil)
end
