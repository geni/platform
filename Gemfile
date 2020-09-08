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

gem 'tr8n', :git => 'https://github.com/geni/tr8n.git', :ref => '48d44bed'
gem "will_filter", :git => 'https://github.com/geni/will_filter.git', :ref => 'abd5ef8'
gem 'will_paginate', "~> 2.3"

group :test do
  gem 'rake', '0.9.2.2'
  gem 'sqlite3'
  gem 'test-unit'
end
