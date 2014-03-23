class Spree::Admin::ProductImportsController < Spree::Admin::BaseController
#Sorry for not using resource_controller railsdog - I wanted to, but then... I did it this way.
#Verbosity is nice?
#Feel free to refactor and submit a pull request.

  def index
    redirect_to :action => :new
  end

  def new
    @product_import = Spree::ProductImport.new
  end


  def create
    @product_import = Spree::ProductImport.create(product_import_params)
    Delayed::Job.enqueue SpreeImportProducts::ImportJob.new(@product_import, spree_current_user)
    flash[:notice] = t('product_import_processing')
    redirect_to admin_product_imports_path
  end

  private

  def product_import_params
    params.require(:product_import).permit(:data_file)
  end

end
