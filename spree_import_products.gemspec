# encoding: UTF-8
Gem::Specification.new do |s|
  s.platform    = Gem::Platform::RUBY
  s.name        = 'spree_import_products'
  s.version     = '2.1.0'
  s.summary     = 'spree_import_products ... imports products. From a CSV file via Spree\'s Admin interface'
  s.required_ruby_version = '>= 1.9.3'

  s.author    = 'sklogan'
  s.email     = 'logan.senthilkumar@gmail.com'
  s.homepage  = 'https://github.com/sklogan/spree_import_products'

  s.require_path = 'lib'
  s.requirements << 'none'

  s.add_dependency 'spree_core', '>=2.1.0'
  s.add_dependency 'delayed_job'
end
