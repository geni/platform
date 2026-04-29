source 'http://rubygems.org'

gemspec

gem "acts_as_state_machine", "~> 2.2.0"
gem "acts_as_tree", "~> 0.1.1"

gem 'rails', '~> 3.2.22'
gem 'tr8n', :git => 'https://github.com/geni/tr8n.git', :branch => 'rails-3.2.x'
gem 'will_filter', :git => 'https://github.com/geni/will_filter.git', :branch => 'rails-3.2.x'

group :test do
  gem 'method_source',    :require => false
  gem 'rake'
  gem 'simplecov'
  # Rails 3.2 uses sqlite3 1.3.13
  gem 'sqlite3', '~> 1.3.13'
  gem 'test-unit', '3.5.7' # 3.6.x have issues with local_name
end

group :vscode do
  # install locally instead
end
