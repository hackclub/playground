require "test_helper"

# The rolling Postgres to Airtable copy, against a fake Airtable.
class AirtableSyncJobTest < ActiveSupport::TestCase
  class FakeAirtable
    attr_reader :upserts
    attr_accessor :existing

    def initialize
      @upserts = []
      @existing = {}
    end

    def upsert(table, rows, merge_on:)
      @upserts << [ table, rows ]
      rows.to_h { [ it[merge_on], { "id" => "rec#{it[merge_on]}", "fields" => it } ] }
    end

    def find_by(_table, _field, values) = existing.slice(*values)
  end

  setup do
    @fake = FakeAirtable.new
    AirtableClient.define_singleton_method(:new) { |*| Thread.current[:fake_airtable] }
    Thread.current[:fake_airtable] = @fake
    Rails.application.config_for(:airtable) # load once
    @config = Rails.application.config_for(:airtable).merge(enabled: true)
    config = @config
    Rails.application.define_singleton_method(:config_for) { |name, **| name == :airtable ? config : super(name) }
  end

  teardown do
    Rails.application.singleton_class.remove_method(:config_for)
    AirtableClient.singleton_class.remove_method(:new)
  end

  def approved_ship
    user = User.create!(hca_id: "ident!s#{SecureRandom.hex(3)}", email: "s@example.com", first_name: "S", verification_status: "verified", ysws_eligible: true)
    project = user.projects.create!(name: "pet", hackatime_projects: [ "p" ], tracked_seconds: 7200)
    admin = User.create!(hca_id: "ident!adm#{SecureRandom.hex(3)}", admin: true)
    ship = project.ships.create!(user:, claimed_seconds: 7200, snapshot: { "projects" => { "p" => 7200 }, "code_url" => "https://github.com/a/b" })
    ship.approve_review!(by: admin, seconds: 7200, judgement: "fine", feedback: nil)
    ship.pass_fraud!(by: admin)
    ship
  end

  test "copies never-synced users first and marks them synced" do
    User.create!(hca_id: "ident!u1", email: "u1@example.com")
    Airtable::SyncJob.perform_now
    table, rows = @fake.upserts.first
    assert_equal "Users", table
    assert rows.any? { it["Email"] == "u1@example.com" && it["Loops - playgroundSignupAt"] }
    assert User.where(synced_at: nil).none?
  end

  test "copies approved ships with hours and justification, but not pending ones" do
    ship = approved_ship
    pending = ship.project.ships.create!(user: ship.user, claimed_seconds: 60)
    Airtable::SyncJob.perform_now
    _, rows = @fake.upserts.find { it.first == "YSWS Project Submission" }
    assert_equal [ "ship-#{ship.id}" ], rows.map { it["playground_id"] }
    row = rows.first
    assert_equal 2.0, row["Optional - Override Hours Spent"]
    assert_includes row["Optional - Override Hours Spent Justification"], "Reviewer judgement: fine"
    assert_equal "fine", row["Justification - Specific Technical Features"]
    assert_match "p (2h 0m)", row["Justification - Hackatime Project Name(s) + Date Range(s)"]
    assert_equal "a", row["GitHub Username"]
    refute row.key?("idv_rec"), "Submit fields are gone"
    refute rows.first.key?("Automation - Submit to Unified YSWS")
    assert_nil pending.reload.airtable_record_id
  end

  # The field names the sync writes must all exist in the real base. Names read
  # from the YSWS Project Submission table on 2026-09-23, plus playground_id.
  SUBMISSION_FIELDS = [
    "playground_id", "Code URL", "Playable URL", "First Name", "Last Name", "Email", "Screenshot", "Description",
    "GitHub Username", "Address (Line 1)", "Address (Line 2)", "City", "State / Province", "Country",
    "ZIP / Postal Code", "Birthday", "Optional - Override Hours Spent", "Optional - Override Hours Spent Justification",
    "Justification - Hackatime Project Name(s) + Date Range(s)", "Justification - Submitter Hackatime ID",
    "Justification - Specific Technical Features", "Justification - Deflation Justification",
    "Justification - Lapse Links, comma-separated"
  ].freeze

  test "every field a ship row writes exists in the submission table" do
    row = AirtableFields.ship(approved_ship)
    assert_empty row.keys - SUBMISSION_FIELDS
  end

  test "never overwrites a ship the Unified DB has taken" do
    ship = approved_ship
    @fake.existing = { "ship-#{ship.id}" => { "fields" => { "Automation - YSWS Record ID" => "recUNIFIED" } } }
    Airtable::SyncJob.perform_now
    assert_nil @fake.upserts.find { it.first == "YSWS Project Submission" }
    assert ship.reload.in_unified
  end

  test "a user row never writes the Loops list, which the base computes" do
    user = User.create!(hca_id: "ident!u3", email: "u3@example.com")
    assert_not AirtableFields.user(user).key?("Loops List - Playground")
  end

  test "a first pet's time goes to Loops, and stays when that pet is deleted" do
    user = User.create!(hca_id: "ident!u4", email: "u4@example.com")
    assert_not AirtableFields.user(user).key?("Loops - playgroundFirstPetCreatedAt")
    user.update_column(:synced_at, Time.current)
    first = user.projects.create!(name: "first")
    travel 1.hour do
      user.projects.create!(name: "second")
      first.destroy!
    end
    user.reload
    assert_nil user.synced_at, "the owner's row syncs next"
    assert_equal first.created_at.iso8601, AirtableFields.user(user)["Loops - playgroundFirstPetCreatedAt"]
  end

  test "a user row carries the address from Hack Club Auth, read at most once a day" do
    user = User.create!(hca_id: "ident!u5", email: "u5@example.com", first_name: "Five")
    Airtable::SyncJob.perform_now
    row = @fake.upserts.first.last.find { it["Email"] == "u5@example.com" }
    assert_equal [ "15 Falls Road", "Unit 2", "Shelburne", "VT", "05482", "US" ],
                 row.values_at("Address (Line 1)", "Address (Line 2)", "City", "State / Province", "ZIP / Postal Code", "Country")
    assert user.reload.address_synced_at

    user.update_column(:synced_at, nil)
    Airtable::SyncJob.perform_now
    row = @fake.upserts.last.last.find { it["Email"] == "u5@example.com" }
    assert_not row.key?("Address (Line 1)"), "the address waits a day before it is read again"
  end

  test "a failed address read leaves the address fields alone and tries again next time" do
    user = User.create!(hca_id: "ident!u6", email: "u6@example.com")
    real = HackClubAuth.method(:for)
    HackClubAuth.define_singleton_method(:for) { |*| raise HttpJson::Error, "down" }
    Airtable::SyncJob.perform_now
    row = @fake.upserts.first.last.find { it["Email"] == "u6@example.com" }
    assert_not row.key?("Address (Line 1)")
    assert_nil user.reload.address_synced_at
  ensure
    HackClubAuth.define_singleton_method(:for, real) if real
  end

  test "does nothing while disabled" do
    @config[:enabled] = false
    User.create!(hca_id: "ident!u2")
    Airtable::SyncJob.perform_now
    assert_empty @fake.upserts
  end
end
