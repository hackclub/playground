# How many browsers read Stardance's guide or the clubs' guide for 20
# minutes or more on each US Eastern day: a count per day and guide, and
# nothing about who.
class CreateGuideReaderDays < ActiveRecord::Migration[8.1]
  def change
    create_table :guide_reader_days do |t|
      t.date :day, null: false
      t.string :guide, null: false
      t.integer :readers, null: false, default: 0
    end
    add_index :guide_reader_days, %i[day guide], unique: true
  end
end
