# The hours of Stardance's playground mission in each stage, as last read
# from Stardance's database: one row of totals, replaced on each read, and
# nothing about who or which project.
class CreateStardanceHours < ActiveRecord::Migration[8.1]
  def change
    create_table :stardance_hours do |t|
      t.integer :approved_seconds, null: false, default: 0
      t.integer :pending_seconds, null: false, default: 0
      t.integer :unshipped_seconds, null: false, default: 0
      t.integer :returned_seconds, null: false, default: 0
      t.integer :projects, null: false, default: 0
      t.integer :left_out_projects, null: false, default: 0
      t.integer :left_out_seconds, null: false, default: 0
      t.timestamps
    end
  end
end
