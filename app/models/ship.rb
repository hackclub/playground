# One submission of a project. Review comes first, then fraud. Pending hours
# become approved hours only when both pass, so the participant never sees a
# silent reject.
#
#   state          pending -> approved | changes_needed | rejected
#   review_status  pending -> approved | changes_needed | rejected
#   fraud_status   waiting -> pending -> passed | deducted | banned
class Ship < ApplicationRecord
  STATES = %w[pending approved changes_needed rejected].freeze
  # Art time, tracked through Lapse, counts for at most this share of the
  # approved hours.
  ART_CAP_PERCENT = 30

  belongs_to :project
  belongs_to :user
  belongs_to :reviewer, class_name: "User", optional: true
  belongs_to :fraud_reviewer, class_name: "User", optional: true
  has_many :claims, as: :claimable, dependent: :delete_all

  validates :state, inclusion: { in: STATES }

  scope :awaiting_review, -> { where(state: "pending", review_status: "pending").order(:created_at) }
  scope :awaiting_fraud, -> { where(state: "pending", fraud_status: "pending").order(:reviewed_at) }

  after_update :mark_unsynced, if: -> { saved_change_to_state? || saved_change_to_approved_seconds? }

  after_update_commit :email_participant, if: :saved_change_to_state?

  STATES.each { |s| define_method(:"#{s}?") { state == s } }

  def number = project.ships.index(self).to_i + 1

  def approve_review!(by:, seconds:, judgement:, feedback:)
    raise ArgumentError, "the reviewer writes a judgement" if judgement.blank?
    update!(review_status: "approved", reviewer: by, reviewed_at: Time.current,
            review_seconds: seconds.clamp(0, claimed_seconds), review_judgement: judgement,
            review_feedback: feedback, fraud_status: "pending")
    AuditEvent.record(by, self, "review.approve", seconds: review_seconds)
  end

  def return_for_changes!(by:, judgement:, feedback:)
    raise ArgumentError, "tell the participant what to change" if feedback.blank?
    update!(review_status: "changes_needed", state: "changes_needed", reviewer: by, reviewed_at: Time.current,
            review_judgement: judgement, review_feedback: feedback)
    AuditEvent.record(by, self, "review.changes")
  end

  def reject_review!(by:, judgement:, feedback:)
    raise ArgumentError, "the reviewer writes a judgement" if judgement.blank?
    update!(review_status: "rejected", state: "rejected", reviewer: by, reviewed_at: Time.current,
            review_judgement: judgement, review_feedback: feedback)
    AuditEvent.record(by, self, "review.reject")
  end

  # The fraud stage ends the ship. Deduction is in seconds; 0 is a plain pass.
  def pass_fraud!(by:, deduction_seconds: 0, notes: nil)
    deduction = deduction_seconds.to_i.clamp(0, review_seconds.to_i)
    raise ArgumentError, "explain the deduction" if deduction.positive? && notes.blank?
    update!(fraud_status: deduction.positive? ? "deducted" : "passed", fraud_reviewer: by,
            fraud_reviewed_at: Time.current, fraud_deduction_seconds: deduction, fraud_notes: notes,
            approved_seconds: review_seconds.to_i - deduction, state: "approved")
    AuditEvent.record(by, self, "fraud.pass", deduction_seconds: deduction)
  end

  def ban_for_fraud!(by:, notes:)
    raise ArgumentError, "record the evidence" if notes.blank?
    transaction do
      update!(fraud_status: "banned", fraud_reviewer: by, fraud_reviewed_at: Time.current,
              fraud_notes: notes, state: "rejected", review_feedback: review_feedback.presence || "This project was rejected.")
      user.ships.where(state: "pending").where.not(id: id).find_each do |other|
        other.update!(state: "rejected", review_status: "rejected", fraud_status: "banned", fraud_notes: "banned with ship #{id}")
      end
      user.ban!(notes, by: by)
    end
    AuditEvent.record(by, self, "fraud.ban")
  end

  def deflated_seconds = claimed_seconds - review_seconds.to_i

  private

  # One email per move into approved or changes_needed. A re-save leaves the
  # state alone, so it never reaches here. A rejection or a ban sends nothing.
  def email_participant
    ShipMailer.notify(self) if state.in?(%w[approved changes_needed])
  end

  def mark_unsynced = update_column(:synced_at, nil)
end
