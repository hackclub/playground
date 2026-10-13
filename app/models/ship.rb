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

  # Where a ship is in the pipeline, for the admin overview. A fraud ban ends
  # in the rejected stage.
  STAGES = {
    "awaiting_review" => "awaiting review", "awaiting_fraud" => "awaiting fraud check",
    "approved" => "approved", "changes_needed" => "changes needed", "rejected" => "rejected"
  }.freeze

  scope :in_stage, lambda { |stage|
    case stage
    when "awaiting_review" then where(state: "pending", review_status: "pending")
    when "awaiting_fraud" then where(state: "pending", fraud_status: "pending")
    when *STAGES.keys then where(state: stage)
    else none
    end
  }

  after_update :mark_unsynced, if: -> { saved_change_to_state? || saved_change_to_approved_seconds? }

  after_update_commit :message_participant, if: :saved_change_to_state?

  STATES.each { |s| define_method(:"#{s}?") { state == s } }

  def stage
    return state unless state == "pending"
    review_status == "pending" ? "awaiting_review" : "awaiting_fraud"
  end

  def number = project.ships.index(self).to_i + 1

  # The review form fills hours rounded to 0.01 h (36 s), so a figure that
  # close to the claim is the claim itself, not a deflation.
  FORM_ROUNDING_SECONDS = 36

  # `seconds` is the approved coding time, `art_seconds` the approved art
  # time (nil takes the most the rules allow). Coding is held to the AI cap.
  # Art is held to ART_CAP_PERCENT of the approved total, by itself, with no
  # reason. A reviewer's cut below either limit needs a reason.
  def approve_review!(by:, seconds:, judgement:, feedback:, deflation_reason: nil, art_seconds: nil)
    raise ArgumentError, 'write the "specific technical features" box first. name the features that explain the hours.' if judgement.blank?
    cap = ai_cap_seconds
    seconds = cap if (cap - seconds).abs <= FORM_ROUNDING_SECONDS
    seconds = seconds.clamp(0, cap)
    allowed = art_allowed_seconds(seconds)
    art = art_seconds.nil? ? allowed : art_seconds
    art = allowed if (allowed - art).abs <= FORM_ROUNDING_SECONDS
    art = art.clamp(0, allowed)
    if (cap - seconds >= 60 || allowed - art >= 60) && deflation_reason.blank?
      raise ArgumentError, 'write the "why deflated" box first. say why you approve less than the rules allow.'
    end
    update!(review_status: "approved", reviewer: by, reviewed_at: Time.current,
            review_coding_seconds: seconds, review_art_seconds: art,
            review_seconds: seconds + art, review_judgement: judgement,
            review_deflation_reason: deflation_reason.presence,
            review_feedback: feedback, fraud_status: "pending")
    AuditEvent.record(by, self, "review.approve", seconds: review_seconds)
  end

  # An approved review that has not had its fraud check goes back to the
  # review queue. The state stays pending, so the participant gets no DM, and
  # created_at keeps the ship in its original place in the queue. What the
  # earlier review held is kept in the audit event.
  def send_back_to_review!(by:, reason:)
    raise ArgumentError, "only a ship that waits for the fraud check goes back" unless sent_back_possible?
    raise ArgumentError, 'write the "reason" box first. say why it goes back to review.' if reason.blank?
    transaction do
      AuditEvent.record(by, self, "review.send_back", reason: reason.strip, reviewer_id: reviewer_id, reviewer_name: reviewer&.display_name,
                        reviewed_at: reviewed_at, review_seconds: review_seconds, review_coding_seconds: review_coding_seconds,
                        review_art_seconds: review_art_seconds, review_judgement: review_judgement,
                        review_deflation_reason: review_deflation_reason, review_feedback: review_feedback)
      update!(review_status: "pending", fraud_status: "waiting", reviewer: nil, reviewed_at: nil, review_seconds: nil,
              review_coding_seconds: nil, review_art_seconds: nil, review_judgement: nil, review_feedback: nil,
              review_deflation_reason: nil, review_checklist: {})
    end
  end

  def sent_back_possible? = state == "pending" && review_status == "approved" && fraud_status == "pending"

  def return_for_changes!(by:, judgement:, feedback:)
    raise ArgumentError, 'write the "note to the participant" box first. say what to change.' if feedback.blank?
    update!(review_status: "changes_needed", state: "changes_needed", reviewer: by, reviewed_at: Time.current,
            review_judgement: judgement, review_feedback: feedback)
    AuditEvent.record(by, self, "review.changes")
  end

  def reject_review!(by:, judgement:, feedback:)
    raise ArgumentError, 'write the "specific technical features" box first. for reject, say what is missing.' if judgement.blank?
    update!(review_status: "rejected", state: "rejected", reviewer: by, reviewed_at: Time.current,
            review_judgement: judgement, review_feedback: feedback)
    AuditEvent.record(by, self, "review.reject")
  end

  # The fraud stage ends the ship. Deduction is in seconds; 0 is a plain pass.
  def pass_fraud!(by:, deduction_seconds: 0, notes: nil)
    deduction = deduction_seconds.to_i.clamp(0, review_seconds.to_i)
    raise ArgumentError, 'write the "notes" box first. explain the deduction.' if deduction.positive? && notes.blank?
    update!(fraud_status: deduction.positive? ? "deducted" : "passed", fraud_reviewer: by,
            fraud_reviewed_at: Time.current, fraud_deduction_seconds: deduction, fraud_notes: notes,
            approved_seconds: review_seconds.to_i - deduction, state: "approved")
    AuditEvent.record(by, self, "fraud.pass", deduction_seconds: deduction)
  end

  # Called from the fraud stage, or from review when the fraud is clear. From
  # review the ship is also rejected there, by the same reviewer.
  def ban_for_fraud!(by:, notes:, judgement: nil)
    if notes.blank?
      box = review_status == "pending" ? "evidence" : "notes"
      raise ArgumentError, "write the \"#{box}\" box first. say what shows the fraud."
    end
    transaction do
      from_review = review_status == "pending"
      if from_review
        assign_attributes(review_status: "rejected", reviewer: by, reviewed_at: Time.current, review_judgement: judgement.presence)
      end
      update!(fraud_status: "banned", fraud_reviewer: by, fraud_reviewed_at: Time.current,
              fraud_notes: notes, state: "rejected", review_feedback: review_feedback.presence || "This project was rejected.")
      user.ships.where(state: "pending").where.not(id: id).find_each do |other|
        other.update!(state: "rejected", review_status: "rejected", fraud_status: "banned", fraud_reviewer: by,
                      fraud_reviewed_at: Time.current, fraud_notes: "banned with ship #{id}")
      end
      user.ban!(notes, by: by)
    end
    AuditEvent.record(by, self, "fraud.ban")
  end

  # Hackatime's "ai coding" time counts at a third, so a ship is approved for
  # at most claimed less two thirds of it. Unknown (nil) means no cut.
  def ai_coding_seconds
    value = snapshot["ai_coding_seconds"]
    [ value.to_i, claimed_seconds ].min unless value.nil?
  end

  # Art is the ship's Lapse time, part of the claimed total. Coding is the rest.
  def art_claimed_seconds = [ snapshot["lapse_seconds"].to_i, claimed_seconds ].min
  def coding_claimed_seconds = claimed_seconds - art_claimed_seconds

  # The most coding approves for: the AI time counts at a third. It is all
  # inside coding, never more than coding.
  def ai_cap_seconds
    ai = [ ai_coding_seconds.to_i, coding_claimed_seconds ].min
    [ (coding_claimed_seconds - ai * 2 / 3.0).round, 0 ].max
  end

  # Art counts for at most ART_CAP_PERCENT of coding plus art.
  def art_max_seconds(coding) = (coding * ART_CAP_PERCENT / (100.0 - ART_CAP_PERCENT)).round
  def art_allowed_seconds(coding) = [ art_claimed_seconds, art_max_seconds(coding) ].min

  # Ships reviewed before the split have only a total.
  def split_review? = review_coding_seconds && art_claimed_seconds.positive?

  def deflated_seconds = claimed_seconds - review_seconds.to_i

  private

  # One Slack DM per move into approved, changes_needed, or rejected, a ban
  # included. A re-save leaves the state alone, so it never reaches here.
  # Never raises: a Slack problem must not undo a review.
  def message_participant
    ReviewDmJob.perform_later(id, state) if state.in?(ReviewDm::STATES)
  rescue StandardError => e
    Rails.logger.error("review dm: could not queue the DM for ship #{id}: #{e.class}")
  end

  def mark_unsynced = update_column(:synced_at, nil)
end
