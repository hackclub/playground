class AddSlackPromptDismissedAtToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :slack_prompt_dismissed_at, :datetime
  end
end
