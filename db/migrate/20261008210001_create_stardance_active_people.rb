# Who on Stardance's playground mission was active on each US Eastern day,
# so the admin stats can list them: Slack ID, Stardance display name, and
# seconds. listed marks a day whose people are stored, so days counted
# before are counted again.
class CreateStardanceActivePeople < ActiveRecord::Migration[8.1]
  def change
    create_table :stardance_active_people do |t|
      t.date :day, null: false
      t.string :slack_id, null: false
      t.string :handle
      t.integer :seconds, null: false
      t.timestamps
    end
    add_index :stardance_active_people, %i[day slack_id], unique: true
    add_column :stardance_active_days, :listed, :boolean, null: false, default: false
  end
end
