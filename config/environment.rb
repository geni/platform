# Be sure to restart your server when you modify this file

# Bootstrap the Rails environment, frameworks, and default configuration
require File.join(File.dirname(__FILE__), 'boot')

# Rails 3.0+ uses application.rb for configuration
require File.expand_path('../application', __FILE__)

# Initialize the Rails application
PlatformGem::Application.initialize!
