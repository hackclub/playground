class AddDeflationReasonToShips < ActiveRecord::Migration[8.1]
  def change
    add_column :ships, :review_deflation_reason, :text
  end
end
