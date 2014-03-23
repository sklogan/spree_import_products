# This model is the master routine for uploading products
# Requires Paperclip and CSV to upload the CSV file and read it nicely.

# Original Author:: Josh McArthur
# Author:: Senthil Kumar
# License:: MIT
class Spree::ProductImport < ActiveRecord::Base

  if Spree::Config[:use_s3]
    logger.info "Using S3 bucket"
    has_attached_file :data_file,
                      :storage => :s3,
                      :bucket => Spree::Config[:s3_bucket],
                      :s3_credentials => {
                          :access_key_id => Spree::Config[:s3_access_key],
                          :secret_access_key => Spree::Config[:s3_secret]
                      },
                      :path => ':rails_root/public/spree/csv/:id/:basename.:extension'
  else
    logger.info "Using local storage"
    has_attached_file :data_file,
                      :path => ':rails_root/public/spree/csv/:id/:basename.:extension'
  end

  validates_attachment_presence :data_file

  require 'csv'
  require 'pp'
  require 'open-uri'

  ## Data Importing:
  # List Price maps to Master Price, Current MAP to Cost Price, Net 30 Cost unused
  # Width, height, Depth all map directly to object
  # Image main is created independtly, then each other image also created and associated with the product
  # Meta keywords and description are created on the product model

  def import_data!
    begin
      #Get products *before* import -
      @products_before_import = Spree::Product.all
      @names_of_products_before_import = @products_before_import.map(&:permalink)

      rows = Spree::Config[:use_s3] ? CSV.parse(open(self.data_file.url)) : CSV.read(self.data_file.path)


      if IMPORT_PRODUCT_SETTINGS[:first_row_is_headings]
        col = get_column_mappings(rows[0])
      else
        col = IMPORT_PRODUCT_SETTINGS[:column_mappings]
      end

      log("Importing products for #{self.data_file_file_name} began at #{Time.now}")

      rows[IMPORT_PRODUCT_SETTINGS[:rows_to_skip]..-1].each do |row|
        product_information = {}

        #Automatically map 'mapped' fields to a collection of product information.
        #NOTE: This code will deal better with the auto-mapping function - i.e. if there
        #are named columns in the spreadsheet that correspond to product
        # and variant field names.
        col.each do |key, value|
          product_information[key] = row[value]
        end

        #Manually set available_on if it is not already set
        product_information[:available_on] = DateTime.now - 1.day if product_information[:available_on].nil?
        product_information[:shipping_category_id] = Spree::ShippingCategory.find_or_create_by(name: product_information[:shipping_category]).id

        product_information.delete(:shipping_category)

        #Trim whitespace off the beginning and end of row fields and reencode into utf8
        row.each do |r|
          next unless r.is_a?(String)
          r.gsub!(/\A\s*/, '').chomp!
          r.force_encoding("iso-8859-1").encode!("UTF-8")
        end

        if IMPORT_PRODUCT_SETTINGS[:create_variants]
          field = IMPORT_PRODUCT_SETTINGS[:variant_comparator_field].to_sym
          if p = Spree::Product.where(field => row[col[field]]).limit(1).first
            p.update_column(:deleted_at, nil) if p.deleted_at #Un-delete product if it is there
            p.variants.each { |variant| variant.update_column(:deleted_at, nil) }
            create_variant_for(p, with: product_information)
          else
            next unless create_product_using(product_information)
          end
        else
          next unless create_product_using(product_information)
        end
      end

      if IMPORT_PRODUCT_SETTINGS[:destroy_original_products]
        @products_before_import.each { |p| p.destroy }
      end

      log("Importing products for #{self.data_file_file_name} completed at #{DateTime.now}")

    rescue Exception => exp
      log("An error occurred during import, please check file and try again. (#{exp.message})\n#{exp.backtrace.join('\n')}", :error)
      raise Exception(exp.message)
    end

    #All done!
    return [:notice, "Product data was successfully imported."]
  end


  private

  # create_variant_for
  # This method assumes that some form of checking has already been done to
  # make sure that we do actually want to create a variant.
  # It performs a similar task to a product, but it also must pick up on
  # size/color options
  def create_variant_for(product, options = {:with => {}})
    return if options[:with].nil?

    sku = options[:with][:sku]
    variant = product.variants.find_or_initialize_by(sku: sku)
    variant.option_values = []
    variant.images.destroy_all

    #Remap the options - oddly enough, Spree's product model has master_price and cost_price, while
    #variant has price and cost_price.
    options[:with][:price] = options[:with].delete(:master_price)

    #First, set the primitive fields on the object (prices, etc.)
    options[:with].each do |field, value|
      variant.send("#{field}=", value) if variant.respond_to?("#{field}=")
      applicable_option_type = Spree::OptionType.where("lower(presentation) = :field OR lower(name) = :field",{ field: field.to_s }).limit(1).first
      if applicable_option_type.is_a?(Spree::OptionType)
        product.option_types << applicable_option_type unless product.option_types.include?(applicable_option_type)
        variant.option_values << applicable_option_type.option_values.where("presentation = :value OR name = :value", { value: value })
      end
    end


    if variant.valid?
      variant.save

      #Associate our new variant with any new taxonomies
      IMPORT_PRODUCT_SETTINGS[:taxonomy_fields].each do |field|
        associate_product_with_taxon(variant.product, field.to_s, options[:with][field.to_sym])
      end

      #Finally, attach any images that have been specified
      IMPORT_PRODUCT_SETTINGS[:image_fields].each do |field|
        find_and_attach_image_to(variant, options[:with][field.to_sym])
      end

      #Log a success message
      log("Variant of SKU #{variant.sku} successfully imported.\n")
    else
      log("A variant could not be imported - here is the information we have:\n" +
              "#{pp options[:with]}, :error")
      return false
    end
  end


  # create_product_using
  # This method performs the meaty bit of the import - taking the parameters for the
  # product we have gathered, and creating the product and related objects.
  # It also logs throughout the method to try and give some indication of process.
  def create_product_using(params_hash)

    params_hash[:price] = params_hash.delete(:master_price)
    product = Spree::Product.new

    #The product is inclined to complain if we just dump all params
    # into the product (including images and taxonomies).
    # What this does is only assigns values to products if the product accepts that field.
    params_hash.each do |field, value|
      product.send("#{field}=", value) if product.respond_to?("#{field}=")
    end

    after_product_built(product, params_hash)

    #We can't continue without a valid product here
    unless product.valid?
      log("A product could not be imported - here is the information we have:\n" +
              "#{pp params_hash}, :error")
      return false
    end

    #Just log which product we're processing
    log(product.name)

    #This should be caught by code in the main import code that checks whether to create
    #variants or not. Since that check can be turned off, however, we should double check.
    if @names_of_products_before_import.include? product.permalink
      log("#{product.name} is already in the system.\n")
    else
      #Save the object before creating asssociated objects
      product.save


      #Associate our new product with any taxonomies that we need to worry about
      IMPORT_PRODUCT_SETTINGS[:taxonomy_fields].each do |field|
        associate_product_with_taxon(product, field.to_s, params_hash[field.to_sym])
      end

      #Finally, attach any images that have been specified to the master variant
      IMPORT_PRODUCT_SETTINGS[:image_fields].each do |field|
        find_and_attach_image_to(product.master, params_hash[field.to_sym])
      end

      if IMPORT_PRODUCT_SETTINGS[:multi_domain_importing] && product.respond_to?(:stores)
        begin
          store = Spree::Store.where("id = :store_field OR code = :store_field", { store_field: params_hash[IMPORT_PRODUCT_SETTINGS[:store_field]] }).limit(1).first
          product.stores << store
        rescue
          log("#{product.name} could not be associated with a store. Ensure that Spree's multi_domain extension is installed and that fields are mapped to the CSV correctly.")
        end
      end

      #Log a success message
      log("#{product.name} successfully imported.\n")
    end
    return true
  end

  # get_column_mappings
  # This method attempts to automatically map headings in the CSV files
  # with fields in the product and variant models.
  # If the headings of columns are going to be called something other than this,
  # or if the files will not have headings, then the manual initializer
  # mapping of columns must be used.
  # Row is an array of headings for columns - SKU, Master Price, etc.)
  # @return a hash of symbol heading => column index pairs
  def get_column_mappings(row)
    mappings = {}
    row.each_with_index do |heading, index|
      next if heading.blank?
      mappings[heading.downcase.gsub(/\A\s*/, '').chomp.gsub(/\s/, '_').to_sym] = index
    end
    mappings
  end


  ### MISC HELPERS ####

  #Log a message to a file - logs in standard Rails format to logfile set up in the import_products initializer
  #and console.
  #Message is string, severity symbol - either :info, :warn or :error

  def log(message, severity = :info)
    @rake_log ||= ActiveSupport::Logger.new(IMPORT_PRODUCT_SETTINGS[:log_to])
    message = "[#{Time.now.to_s(:db)}] [#{severity.to_s.capitalize}] #{message}\n"
    @rake_log.send severity, message
    puts message
  end


  ### IMAGE HELPERS ###

  # find_and_attach_image_to
  # This method attaches images to products. The images may come
  # from a local source (i.e. on disk), or they may be online (HTTP/HTTPS).
  def find_and_attach_image_to(product_or_variant, filename)
    return if filename.blank?

    #The image can be fetched from an HTTP or local source - either method returns a Tempfile
    file = filename =~ /\Ahttp[s]*:\/\// ? fetch_remote_image(filename) : fetch_local_image(filename)
    #An image has an attachment (the image file) and some object which 'views' it
    product_image = Spree::Image.new(attachment: file, position: product_or_variant.images.length)
    if product_image.save
      product_image.update_column :viewable, product_or_variant
      product_or_variant.images << product_image
    end

  end

  # This method is used when we have a set location on disk for
  # images, and the file is accessible to the script.
  # It is basically just a wrapper around basic File IO methods.
  def fetch_local_image(filename)
    filename = IMPORT_PRODUCT_SETTINGS[:product_image_path] + filename
    unless File.exists?(filename) && File.readable?(filename)
      log("Image #{filename} was not found on the server, so this image was not imported.", :warn)
      return nil
    else
      return File.open(filename, 'rb')
    end
  end


  #This method can be used when the filename matches the format of a URL.
  # It uses open-uri to fetch the file, returning a Tempfile object if it
  # is successful.
  # If it fails, it in the first instance logs the HTTP error (404, 500 etc)
  # If it fails altogether, it logs it and exits the method.
  def fetch_remote_image(filename)
    begin
      open(filename)
    rescue OpenURI::HTTPError => error
      log("Image #{filename} retrival returned #{error.message}, so this image was not imported")
    rescue
      log("Image #{filename} could not be downloaded, so was not imported.")
    end
  end

  ### TAXON HELPERS ###

  # associate_product_with_taxon
  # This method accepts three formats of taxon hierarchy strings which will
  # associate the given products with taxons:
  # 1. A string on it's own will will just find or create the taxon and
  # add the product to it. e.g. taxonomy = "Category", taxon_hierarchy = "Tools" will
  # add the product to the 'Tools' category.
  # 2. A item > item > item structured string will read this like a tree - allowing
  # a particular taxon to be picked out
  # 3. An item > item & item > item will work as above, but will associate multiple
  # taxons with that product. This form should also work with format 1.
  def associate_product_with_taxon(product, taxonomy, taxon_hierarchy)
    return if product.nil? || taxonomy.nil? || taxon_hierarchy.nil?
    #Using find_or_create_by_name is more elegant, but our magical params code automatically downcases
    # the taxonomy name, so unless we are using MySQL, this isn't going to work.
    taxonomy_name = taxonomy
    taxonomy = Spree::Taxonomy.where("lower(name) = ?", taxonomy).limit(1).first
    taxonomy = Spree::Taxonomy.create(name: taxonomy_name.capitalize) if taxonomy.nil? && IMPORT_PRODUCT_SETTINGS[:create_missing_taxonomies]

    taxon_hierarchy.split(/\s*\&\s*/).each do |hierarchy|
      hierarchy = hierarchy.split(/\s*>\s*/)
      last_taxon = taxonomy.root
      hierarchy.each do |taxon|
        last_taxon = last_taxon.children.find_or_create_by(name: taxon, taxonomy_id: taxonomy.id)
      end

      #Spree only needs to know the most detailed taxonomy item
      product.taxons << last_taxon unless product.taxons.include?(last_taxon)
    end
  end
  ### END TAXON HELPERS ###

  # May be implemented via decorator if useful:
  #
  #    ProductImport.class_eval do
  #
  #      private
  #
  #      def after_product_built(product, params_hash)
  #        # so something with the product
  #      end
  #    end
  def after_product_built(product, params_hash)
  end
end
