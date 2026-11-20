source 'http://rubygems.org'

gemspec

gem "acts_as_state_machine", "~> 2.2.0"
gem "acts_as_tree", "~> 0.1.1"

# This branch is Rails 3.0 and nothing else.  It used to carry a next_rails dual boot -- a `next?`
# helper keyed on the Gemfile's own filename, a Gemfile.next symlink pointing back here, and an
# `if next?` split with Rails 2.3 LTS from makandra on the other side.  That made the branch name a
# statement about only half of what it built, and test_my_app.sh, which never sets BUNDLE_GEMFILE,
# silently exercised the 2.3 half: five branches would have reported green having tested one Rails.
#
# Rails 3.0.20 requires `bundler (~> 1.0)`, so this Gemfile resolves only under bundler 1.x.
gem 'rails', '~>3.0.0'
gem 'tr8n', :git => 'https://github.com/geni/tr8n.git', :branch => 'rails-3.0.x'
gem 'will_filter', :git => 'https://github.com/geni/will_filter.git', :branch => 'rails-3.0.x'

group :test do
  gem 'method_source',    :require => false
  gem 'rake'
  gem 'simplecov'
  gem 'sqlite3', '1.6.9' # last version that works with Ruby 2.7
  gem 'test-unit', '3.6.2' # >3.6.3 have problems with elapsed_time
end

group :vscode do
  # install locally instead
end
