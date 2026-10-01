# A pet holds an ordered list of screenshots, and the first is its cover.
# Each keeps the storage key it was saved under and its public URL. A pet's
# one screenshot becomes the first of its list.
class MoveScreenshotsIntoAList < ActiveRecord::Migration[8.1]
  def up
    add_column :projects, :screenshots, :jsonb, default: [], null: false
    execute <<~SQL
      UPDATE projects
      SET screenshots = jsonb_build_array(jsonb_build_object('id', gen_random_uuid()::text, 'key', screenshot_key, 'url', screenshot_url))
      WHERE screenshot_url IS NOT NULL AND screenshot_url <> ''
    SQL
    remove_column :projects, :screenshot_key
    remove_column :projects, :screenshot_url
  end

  def down
    add_column :projects, :screenshot_url, :string
    add_column :projects, :screenshot_key, :string
    execute <<~SQL
      UPDATE projects SET screenshot_key = screenshots -> 0 ->> 'key', screenshot_url = screenshots -> 0 ->> 'url'
      WHERE jsonb_array_length(screenshots) > 0
    SQL
    remove_column :projects, :screenshots
  end
end
