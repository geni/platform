# not auto-included from gemspec
require 'acts_as_tree'

module Platform
  class Engine < ::Rails::Engine
    isolate_namespace Platform
    config.autoload_paths << root.join('lib')

    def self.mount_point
      return nil unless defined?(Rails) && Rails.application
      @mount_point ||=  begin
        route = Rails.application.routes.routes.find {|ii| ii.app.respond_to?(:app) && ii.app.app == self}
        path = route.path.spec.to_s
        path.gsub(/\([^)]*\)/, '').chomp('/')
      end
    end

    #
    # initializer blocks are excecuted during boot (order can vary)
    #
    initializer 'platform.init' do |app|
    end

    #
    # to_prepare blocks are executed after all classes are loaded
    #
    config.to_prepare do
      WillFilter.configure do |config|
        config.table_name_prefix = 'wf' unless Rails.env.test?
      end
    end

  end
end
