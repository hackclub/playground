# The new site, without the desktop, is behind a flag on each user. It
# starts off, and only an admin turns it on.
class AddNewSiteToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :new_site, :boolean, null: false, default: false
  end
end
