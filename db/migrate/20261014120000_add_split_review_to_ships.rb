class AddSplitReviewToShips < ActiveRecord::Migration[8.1]
  def change
    add_column :ships, :review_coding_seconds, :integer
    add_column :ships, :review_art_seconds, :integer
  end
end
