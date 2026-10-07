# How many browsers reached each section of each guide on each US Eastern
# day: a count per day, guide, and section, and nothing about who.
class CreateGuideSectionDays < ActiveRecord::Migration[8.1]
  def change
    create_table :guide_section_days do |t|
      t.date :day, null: false
      t.string :guide, null: false
      t.string :section, null: false
      t.integer :readers, null: false, default: 0
    end
    add_index :guide_section_days, %i[day guide section], unique: true
  end
end
