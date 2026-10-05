class AddSlackInvitedAtToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :slack_invited_at, :datetime
  end
end
