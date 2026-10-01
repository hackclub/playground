# The playground data model.
#
# users        one per Hack Club Auth identity
# projects     a desktop pet, linked to any number of Hackatime projects
# ships        one per submission of a project; carries the review stage,
#              then the fraud stage, then the approved hours
# redemptions  one per goal a participant redeems; carries fulfillment
# claims       who is working on which item in which admin stage
# audit_events every verdict, and every address reveal
class CreatePlayground < ActiveRecord::Migration[8.1]
  def change
    create_table :users do |t|
      t.string :hca_id, null: false
      t.string :email
      t.string :first_name
      t.string :last_name
      t.string :slack_id
      t.string :verification_status
      t.boolean :ysws_eligible, null: false, default: false
      t.date :birthday
      t.text :hca_access_token
      t.text :hca_refresh_token
      t.text :hackatime_access_token
      t.string :hackatime_user_id
      t.string :hackatime_trust_level
      t.boolean :admin, null: false, default: false
      t.datetime :banned_at
      t.string :ban_reason
      t.string :airtable_record_id
      t.datetime :synced_at
      t.timestamps
    end
    add_index :users, :hca_id, unique: true
    add_index :users, :synced_at

    create_table :projects do |t|
      t.references :user, null: false, foreign_key: true
      t.string :name, null: false
      t.text :description
      t.string :code_url
      t.string :playable_url
      t.string :screenshot_url
      t.string :hackatime_projects, array: true, null: false, default: []
      t.integer :tracked_seconds, null: false, default: 0
      t.datetime :tracked_at
      t.timestamps
    end

    create_table :ships do |t|
      t.references :project, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.string :state, null: false, default: "pending"
      t.integer :claimed_seconds, null: false, default: 0
      t.jsonb :snapshot, null: false, default: {}

      t.string :review_status, null: false, default: "pending"
      t.references :reviewer, foreign_key: { to_table: :users }
      t.datetime :reviewed_at
      t.integer :review_seconds
      t.text :review_judgement
      t.text :review_feedback
      t.jsonb :review_checklist, null: false, default: {}

      t.string :fraud_status, null: false, default: "waiting"
      t.references :fraud_reviewer, foreign_key: { to_table: :users }
      t.datetime :fraud_reviewed_at
      t.integer :fraud_deduction_seconds, null: false, default: 0
      t.text :fraud_notes

      t.integer :approved_seconds
      t.boolean :in_unified, null: false, default: false
      t.string :airtable_record_id
      t.datetime :synced_at
      t.timestamps
    end
    add_index :ships, [ :review_status, :created_at ]
    add_index :ships, [ :fraud_status, :reviewed_at ]
    add_index :ships, :synced_at

    create_table :redemptions do |t|
      t.references :user, null: false, foreign_key: true
      t.string :goal_key, null: false
      t.string :status, null: false, default: "pending"
      t.text :address
      t.references :fulfilled_by, foreign_key: { to_table: :users }
      t.datetime :fulfilled_at
      t.string :tracking
      t.integer :cost_cents
      t.text :notes
      t.string :airtable_record_id
      t.datetime :synced_at
      t.timestamps
    end
    add_index :redemptions, [ :user_id, :goal_key ], unique: true
    add_index :redemptions, [ :status, :created_at ]

    create_table :claims do |t|
      t.references :claimable, polymorphic: true, null: false
      t.string :stage, null: false
      t.references :user, null: false, foreign_key: true
      t.datetime :heartbeat_at, null: false
      t.timestamps
    end
    add_index :claims, [ :claimable_type, :claimable_id, :stage ], unique: true

    create_table :audit_events do |t|
      t.references :actor, foreign_key: { to_table: :users }
      t.references :subject, polymorphic: true
      t.string :action, null: false
      t.jsonb :data, null: false, default: {}
      t.datetime :created_at, null: false
    end
  end
end
