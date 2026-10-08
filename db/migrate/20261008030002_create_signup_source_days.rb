# How many new accounts came from each source on each US Eastern day, as
# counts and nothing about who (SignupSourceDay). No row names or links to
# an account.
class CreateSignupSourceDays < ActiveRecord::Migration[8.1]
  SOURCES = %i[first_source first_medium first_campaign last_source last_medium last_campaign].freeze

  def change
    create_table :signup_source_days do |t|
      t.date :day, null: false
      SOURCES.each { t.string it, null: false, default: "" }
      t.integer :signups, null: false, default: 0
      t.check_constraint "signups >= 0", name: "signup_source_days_signups_not_negative"
    end
    add_index :signup_source_days, [ :day, *SOURCES ], unique: true, name: "index_signup_source_days_uniquely"
  end
end
