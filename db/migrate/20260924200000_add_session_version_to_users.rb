# A login counts while its session carries the account's session version.
# Logging out moves the version on, so no copy of an old session cookie signs
# anyone in again.
class AddSessionVersionToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :session_version, :integer, default: 0, null: false
  end
end
