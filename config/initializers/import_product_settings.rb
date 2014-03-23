# This file is the thing you have to config to match your application

IMPORT_PRODUCT_SETTINGS = {
  :column_mappings => { #Change these for manual mapping of product fields to the CSV file
    sku: 0,
    name: 1,
    master_price: 2,
    cost_price: 3,
    shipping_category: 4,
    weight: 5,
    height: 6,
    width: 7,
    depth: 8,
    image_main: 9,
    image_2: 10,
    image_3: 11,
    image_4: 12,
    description: 13,
    category: 14
  },
  :create_missing_taxonomies => true,
  :taxonomy_fields => [:category, :brand], #Fields that should automatically be parsed for taxons to associate
  :image_fields => [:image_main, :image_2, :image_3, :image_4], #Image fields that should be parsed for image locations
  :product_image_path => "#{Rails.root}/lib/etc/product_data/product-images/", #The location of images on disk
  :rows_to_skip => 1, #If your CSV file will have headers, this field changes how many rows the reader will skip
  :log_to => File.join(Rails.root, '/log/', "import_products_#{Rails.env}.log"), #Where to log to
  :destroy_original_products => false, #Delete the products originally in the database after the import?
  :first_row_is_headings => true, #Reads column names from first row if set to true.
  :create_variants => true, #Compares products and creates a variant if that product already exists.
  :variant_comparator_field => :name, #Which product field to detect duplicates on
  :multi_domain_importing => true, #If Spree's multi_domain extension is installed, associates products with store
  :store_field => :store_code #Which field of the column mappings contains either the store id or store code?
}

