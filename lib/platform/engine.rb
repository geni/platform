module Platform
  class Engine < ::Rails::Engine
    config.generators do |g|
      g.test_framework :test_unit, fixture: false
    end

    # Ensure our app paths are properly configured
    config.autoload_paths << File.expand_path("../../app/models", File.dirname(__FILE__))
    config.autoload_paths << File.expand_path("../../app/controllers", File.dirname(__FILE__))
    config.autoload_paths << File.expand_path("../../app/helpers", File.dirname(__FILE__))
  end
end
