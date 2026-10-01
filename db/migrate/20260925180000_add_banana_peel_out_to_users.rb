# Whether a participant took the banana peel out of their desktop trash
# themselves. Until they do, it is in their trash, even in one saved before
# it came.
class AddBananaPeelOutToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :banana_peel_out, :boolean, default: false, null: false
  end
end
