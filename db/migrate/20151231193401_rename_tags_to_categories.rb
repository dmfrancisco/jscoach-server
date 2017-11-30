class RenameTagsToCategories < ActiveRecord::Migration[5.1]
  def change
    rename_table :tags, :categories
    rename_table :packages_tags, :categories_packages
    rename_column :categories_packages, :tag_id, :category_id
  end
end
