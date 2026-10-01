# Seconds each participant coded in each hour, from Hackatime's heartbeat
# spans, for the admin heatmap. hour is the UTC start of an hour; an hour
# with no time has no row. CodingHoursJob fills it, and
# users.coding_hours_synced_at records when a participant's rows were last
# fetched.
class CreateCodingHours < ActiveRecord::Migration[8.1]
  def change
    create_table :coding_hours do |t|
      # The unique index below leads with user_id, so it is the user_id index.
      t.references :user, null: false, foreign_key: true, index: false
      t.datetime :hour, null: false
      t.integer :seconds, null: false
      t.timestamps
      t.check_constraint "seconds BETWEEN 0 AND 3600", name: "coding_hours_seconds_fit_the_hour"
      t.check_constraint "hour = date_trunc('hour', hour)", name: "coding_hours_hour_is_whole"
    end
    add_index :coding_hours, [ :user_id, :hour ], unique: true
    add_index :coding_hours, :hour

    add_column :users, :coding_hours_synced_at, :datetime
  end
end
