# The R2 object key of the uploaded screenshot. screenshot_url stays as the
# public URL on playground.hackclub-assets.com.
class AddScreenshotKeyToProjects < ActiveRecord::Migration[8.1]
  def change
    add_column :projects, :screenshot_key, :string
  end
end
