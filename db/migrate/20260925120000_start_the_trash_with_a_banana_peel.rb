# A new account's trash starts with a banana peel in it. An account made
# before keeps the trash it has, empty or not.
class StartTheTrashWithABananaPeel < ActiveRecord::Migration[8.1]
  def change
    change_column_default :users, :desktop_trash, from: [], to: [ "banana peel" ]
  end
end
