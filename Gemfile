source 'http://rubygems.org'

gemspec

gem "acts_as_state_machine", "~> 2.2.0"
gem "acts_as_tree", "~> 0.1.1"

# Rails LTS sources for free Community plan
git 'https://github.com/makandra/rails.git', :branch => '2-3-lts' do
  gem 'rails', '~>2.3.18'
#  gem 'actionmailer',     :require => false
  gem 'actionpack',       :require => false
  gem 'activerecord',     :require => false
#  gem 'activeresource',   :require => false
  gem 'activesupport',    :require => false
  gem 'railties',         :require => false
end

gem 'tr8n', :git => 'https://github.com/geni/tr8n.git', :branch => 'rails-2.3.x'
gem "will_filter", :git => 'https://github.com/geni/will_filter.git', :branch => 'rails-2.3.x'
gem 'will_paginate', "~> 2.3"

group :test do
  gem 'method_source',    :require => false
  gem 'rake'
  gem 'simplecov'
  gem 'sqlite3'
  gem 'test-unit', '3.6.2' # >3.6.3 have problems with elapsed_time
end

group :vscode do
  gem 'debase',         :require => false
  gem 'ruby-debug-ide', :require => false
  gem 'solargraph',     :require => false
end