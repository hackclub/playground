# When NoTimeNudge marked a participant as due the "no time yet" email.
class AddNoTimeNudgeAtToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :no_time_nudge_at, :datetime
  end
end
