# Settings specified here will take precedence over those in config/environment.rb

# Rails 3.0+ wraps configuration in PlatformGem::Application.configure block
if defined?(PlatformGem::Application)
  PlatformGem::Application.configure do
    # In the development environment your application's code is reloaded on
    # every request.  This slows down response time but is perfect for development
    # since you don't have to restart the webserver when you make code changes.
    config.cache_classes = false

    # Log error messages when you accidentally call methods on nil.
    config.whiny_nils = true

    # Show full error reports and disable caching
    config.consider_all_requests_local       = true
    config.action_controller.perform_caching = false

    # Don't care if the mailer can't send
    config.action_mailer.raise_delivery_errors = false

    # Print deprecation notices to the Rails logger
    config.active_support.deprecation = :log

    # Only use best-standards-support built into browsers
    config.action_dispatch.best_standards_support = :builtin
  end
else
  # Rails 2.3 style - these are evaluated inside a config block in environment.rb
  config.cache_classes = false
  config.whiny_nils = true
  config.action_controller.consider_all_requests_local = true
  config.action_view.debug_rjs                         = true
  config.action_controller.perform_caching             = false
  config.action_mailer.raise_delivery_errors = false
end
