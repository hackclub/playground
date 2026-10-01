# Who is working on an item in one admin stage. A claim goes stale 90 seconds
# after its last heartbeat, and then anyone may take it (the rule horizons
# uses for its review queue).
class Claim < ApplicationRecord
  STALE_AFTER = 90.seconds
  STAGES = %w[review fraud fulfillment].freeze

  belongs_to :claimable, polymorphic: true
  belongs_to :user

  validates :stage, inclusion: { in: STAGES }

  scope :live, -> { where(heartbeat_at: STALE_AFTER.ago..) }

  def live? = heartbeat_at > STALE_AFTER.ago

  # Returns [claim, took_it]. A live claim held by someone else is left alone
  # unless force is true.
  def self.acquire(item, stage, user, force: false)
    claim = find_or_initialize_by(claimable: item, stage: stage)
    return [ claim, false ] if claim.persisted? && claim.user_id != user.id && claim.live? && !force

    claim.update!(user: user, heartbeat_at: Time.current)
    [ claim, true ]
  rescue ActiveRecord::RecordNotUnique
    retry
  end

  def self.held_by_other?(item, stage, user)
    live.where(claimable: item, stage: stage).where.not(user: user).exists?
  end
end
