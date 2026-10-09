# The rolling copy of Postgres rows to the program base.
# Every minute, for each table, it upserts the 10 rows with the oldest
# synced_at, never-synced rows first. A change to a row sets synced_at back to
# nil, so the row goes next. The ship copy never overwrites a row the Unified
# DB has taken. It sets "Automation - Submit to Unified YSWS" on a ship it
# copies, unless the ship's repo is shipped on Stardance (StardanceRepos), so
# the work is not paid twice. If that list can't be read, no ship in the batch
# is checked, and a person decides.
module Airtable
  class SyncJob < ApplicationJob
    queue_as :default
    limits_concurrency to: 1, key: "airtable-sync" if respond_to?(:limits_concurrency)

    BATCH = 10
    UNIFIED_FIELD = "Automation - YSWS Record ID"
    # How often a user's address is read again from Hack Club Auth.
    ADDRESS_EVERY = 1.day

    def perform
      config = Rails.application.config_for(:airtable)
      return unless config[:enabled]

      @client = AirtableClient.new
      @tables = config[:tables]
      sync_users
      sync_ships
      sync_redemptions
    end

    private

    def stale(scope) = scope.order(Arel.sql("synced_at ASC NULLS FIRST")).limit(BATCH).to_a

    def address_due?(user) = user.address_synced_at.nil? || user.address_synced_at < ADDRESS_EVERY.ago

    # A user's address comes from Hack Club Auth, at most once a day each, and
    # a failed read leaves the fields as they were until the next pass.
    def sync_users
      users = stale(User.all)
      return if users.empty?
      addresses = users.filter_map { |u| [ u.id, AirtableFields.user_address(u) ] if address_due?(u) }.to_h.compact
      rows = users.map { |u| AirtableFields.user(u).merge(addresses[u.id] || {}) }
      @client.upsert(@tables[:users], rows, merge_on: "playground_id").each do |key, record|
        User.where(id: key.delete_prefix("user-")).update_all(airtable_record_id: record["id"])
      end
      User.where(id: addresses.keys).update_all(address_synced_at: Time.current)
    ensure
      User.where(id: users.map(&:id)).update_all(synced_at: Time.current) if users&.any?
    end

    # Only final ships cross: approved after review and fraud.
    def sync_ships
      ships = stale(Ship.where(state: "approved", in_unified: false).includes(:user, :project, :reviewer, :fraud_reviewer))
      return if ships.empty?
      existing = @client.find_by(@tables[:ships], "playground_id", ships.map { "ship-#{it.id}" })
      taken, fresh = ships.partition { existing.dig("ship-#{it.id}", "fields", UNIFIED_FIELD).present? }
      Ship.where(id: taken.map(&:id)).update_all(in_unified: true)
      return if fresh.empty?
      stardance = stardance_repos
      rows = fresh.map { AirtableFields.ship(it, unified: unified?(it, stardance)) }
      @client.upsert(@tables[:ships], rows, merge_on: "playground_id").each do |key, record|
        Ship.where(id: key.delete_prefix("ship-")).update_all(airtable_record_id: record["id"])
      end
    ensure
      Ship.where(id: ships.map(&:id)).update_all(synced_at: Time.current) if ships&.any?
    end

    # The normalized repo URLs shipped on Stardance, or nil when they can't be
    # read, which leaves every ship in the batch unchecked.
    def stardance_repos
      StardanceRepos.keys
    rescue => e
      Rails.logger.error("Stardance shipped repos not read (#{e.class}); no ship is checked for the Unified DB")
      nil
    end

    def unified?(ship, stardance)
      code_url = ship.snapshot["code_url"]
      !stardance.nil? && UnifiedSearch.normalize(code_url).present? && !StardanceRepos.shipped?(code_url, stardance)
    end

    def sync_redemptions
      redemptions = stale(Redemption.all.includes(:user))
      return if redemptions.empty?
      @client.upsert(@tables[:redemptions], redemptions.map { AirtableFields.redemption(it) }, merge_on: "playground_id")
    ensure
      Redemption.where(id: redemptions.map(&:id)).update_all(synced_at: Time.current) if redemptions&.any?
    end
  end
end
