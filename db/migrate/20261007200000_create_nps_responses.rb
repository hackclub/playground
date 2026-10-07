# Answers to the NPS form (NpsResponse). Which of the text answers are
# required is a rule in the model, so the columns allow empty.
class CreateNpsResponses < ActiveRecord::Migration[8.1]
  def change
    create_table :nps_responses do |t|
      t.references :user, null: false, index: false, foreign_key: { on_delete: :cascade }
      t.references :project, foreign_key: { on_delete: :nullify }
      t.integer :score, null: false
      t.text :doing_well
      t.text :improve
      t.text :anything_else
      t.string :source, null: false
      t.timestamps
    end
    add_index :nps_responses, %i[user_id created_at]
    add_index :nps_responses, :created_at
    add_check_constraint :nps_responses, "score BETWEEN 0 AND 10", name: "nps_responses_score_0_to_10"
  end
end
