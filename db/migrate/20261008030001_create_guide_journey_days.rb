# How far readers get in each guide and how long they spend on it, by where
# they came from, as counts and nothing about who (GuideJourneyDay). A row
# counts the browsers that started the guide on the day, came from the
# sources named, and have reached at least the stage and at least the
# minutes. Counts only ever go up.
class CreateGuideJourneyDays < ActiveRecord::Migration[8.1]
  SOURCES = %i[first_source first_medium first_campaign last_source last_medium last_campaign].freeze

  def change
    create_table :guide_journey_days do |t|
      t.date :day, null: false
      t.string :guide, null: false
      t.string :stage, null: false
      t.integer :minutes, null: false
      SOURCES.each { t.string it, null: false, default: "" }
      t.integer :readers, null: false, default: 0
      t.check_constraint "readers >= 0", name: "guide_journey_days_readers_not_negative"
      t.check_constraint "minutes IN (0, 2, 5, 10, 20, 40, 60)", name: "guide_journey_days_minutes_bucket"
    end
    add_index :guide_journey_days, [ :guide, :day, :stage, :minutes, *SOURCES ], unique: true, name: "index_guide_journey_days_uniquely"
  end
end
