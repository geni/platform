source 'http://rubygems.org'

gemspec

gem "acts_as_state_machine", "~> 2.2.0"
gem "acts_as_tree", "~> 0.1.1"

# Rails LTS sources for free Community plan
git 'https://github.com/makandra/rails.git', :branch => '2-3-lts' do
  gem 'rails', '~>2.3.18'
  gem 'actionmailer',     :require => false
  gem 'actionpack',       :require => false
  gem 'activerecord',     :require => false
  gem 'activeresource',   :require => false
  gem 'activesupport',    :require => false
  gem 'railties',         :require => false
  gem 'railslts-version', :require => false
end

gem 'tr8n', :git => 'https://github.com/geni/tr8n.git', :ref => '388b997'
gem "will_filter", :git => 'https://github.com/geni/will_filter.git', :ref => 'a5201ca'
gem 'will_paginate', "~> 2.3"

group :test do
  gem 'method_source',    :require => false
  gem 'rake', '10.5.0'
  gem 'simplecov'
  gem 'simplecov-html'
  gem 'sqlite3'
  gem 'test-unit', '1.2.3'
  gem 'webrick'
end

group :vscode do
  gem "debase",           :require => false
  gem "debug",            :require => false
  gem "rdoc", '6.2.1.1',  :require => false
  gem "ruby-debug-ide",   :require => false
end