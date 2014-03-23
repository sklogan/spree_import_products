class CreateSpreeProductImports < ActiveRecord::Migration
  def change
    create_table :spree_product_imports do |t|
      t.string :data_file_file_name
      t.string :data_file_content_type
      t.integer :data_file_file_size
      t.datetime :data_file_updated_at

      t.timestamps
    end
  end
end
