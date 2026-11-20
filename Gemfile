source 'http://rubygems.org'

gemspec

gem "acts_as_state_machine", "~> 2.2.0"
gem "acts_as_tree", "~> 0.1.1"

# This branch is Rails 3.1 and nothing else.  It used to carry a next_rails dual boot -- a `next?`
# helper keyed on the Gemfile's own filename, a Gemfile.next symlink pointing back here, and
# `if next?` splits holding Rails 3.0.20 on the other side.  upgrade_path.md has always ended with
# "remove the old code so its only rails <next version> compatible"; this is that step.
gem 'rails', '~> 3.1.12'
gem 'tr8n', :git => 'https://github.com/geni/tr8n.git', :branch => 'rails-3.1.x'
gem 'will_filter', :git => 'https://github.com/geni/will_filter.git', :branch => 'rails-3.1.x'

group :test do
  gem 'method_source',    :require => false
  gem 'rake'
  gem 'simplecov'
  # Last of the 1.3.x series, which is what Rails 3.1 works with.  The 3.0 side of the dual boot
  # needed 1.6.9 instead, which is why this used to be conditional.
  gem 'sqlite3', '~> 1.3.13'
  gem 'test-unit', '3.5.7' # 3.6.x have issues with local_name
end

group :vscode do
  # install locally instead
end
