Deface::Override.new(:virtual_path => "spree/admin/shared/_menu",
                     :name => "import_admin_tabs",
                     :insert_bottom => "[data-hook='admin_tabs']",
                     :text => "<%= tab(:product_imports, url: spree.admin_product_imports_path, icon: 'icon-upload') %>",
                     :disabled => false)
