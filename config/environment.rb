# Be sure to restart your server when you modify this file

# Bootstrap the Rails environment, frameworks, and default configuration
require File.join(File.dirname(__FILE__), 'boot')
require File.expand_path('../application', __FILE__)

PlatformGem::Application.initialize!

# This file used to end with a `Rails::Initializer.run do |config| ... end` block, and -- on the
# Rails 3.0 side of the dual boot -- a shim that defined Rails::Initializer.run as a no-op taking a
# block, so that the block could be parsed and then thrown away.  Both are gone.
#
# Nothing is lost by dropping them: the two settings that block carried, `config.time_zone = 'UTC'`
# and `config.rails_lts_options`, were already being discarded by that no-op whenever this branch
# ran as Rails 3.0.  config/application.rb already sets time_zone to UTC, and rails_lts_options was
# only ever meaningful to the makandra Rails 2.3 LTS gem, which this branch no longer depends on.
# Nothing else in the gem calls Rails::Initializer.
