# When the sync last read a user's address from Hack Club Auth for the
# Users table. The address itself is never stored here.
class AddAddressSyncedAtToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :address_synced_at, :datetime
  end
end
