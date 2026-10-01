# The name playground shows for a person: their Slack display name, or a
# generated two-part name. Full names appear only where shipping needs them.
class AddDisplayNameToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :display_name, :string
    add_column :users, :display_name_source, :string
  end
end
