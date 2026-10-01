class AddShipMessageUrlToProjects < ActiveRecord::Migration[8.1]
  def change
    add_column :projects, :ship_message_url, :string
  end
end
