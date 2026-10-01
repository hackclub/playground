# When each participant made their first pet, for the Loops event
# playgroundFirstPetCreatedAt. Participants with pets take their oldest.
class AddFirstPetCreatedAtToUsers < ActiveRecord::Migration[8.1]
  def up
    add_column :users, :first_pet_created_at, :datetime
    execute <<~SQL
      UPDATE users SET first_pet_created_at = firsts.created_at
      FROM (SELECT user_id, MIN(created_at) AS created_at FROM projects GROUP BY user_id) AS firsts
      WHERE firsts.user_id = users.id
    SQL
  end

  def down
    remove_column :users, :first_pet_created_at
  end
end
