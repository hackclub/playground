# How many people on Stardance's playground mission were active on each US
# Eastern day by their Hackatime time, and how many could not be counted:
# a count per day, and nothing about who.
class CreateStardanceActiveDays < ActiveRecord::Migration[8.1]
  def change
    create_table :stardance_active_days do |t|
      t.date :day, null: false, index: { unique: true }
      t.integer :active, null: false, default: 0
      t.integer :unknown, null: false, default: 0
      t.timestamps
    end
  end
end
