# The desktop icons a participant has dragged into the trash, by icon, so the
# trash follows them from one browser to the next. Pets never go in it.
class AddDesktopTrashToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :desktop_trash, :string, array: true, default: [], null: false
  end
end
