class AddCollectionAndPositionColumnsToFilters < ActiveRecord::Migration[5.1]
  def change
    add_reference :filters, :collection, index: true, foreign_key: true, null: false
    add_column :filters, :position, :integer
  end
end
