# not auto-included from gemspec
require 'acts_as_tree'

module Platform
  class Engine < ::Rails::Engine
    isolate_namespace Platform
    config.autoload_paths << root.join('lib')

    def self.mount_point(route_set=nil)
      return nil unless defined?(Rails) && Rails.application
      @mount_point ||=  begin
        route_set ||= Rails.application.routes
        path        = nil

        route_set.routes.each do |route|
          break if path
          next unless route.app.app.is_a?(Class) && route.app.app < Rails::Engine
          if route.app.app == self
            path = route.path.spec.to_s
          elsif route.app.app.respond_to?(:routes)
            path = mount_point(route.app.app.routes)
          end
        end

        path.gsub(/\([^)]*\)/, '').chomp('/') if path
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
        # Set in every environment, test included.  It used to be skipped in test, which left
        # WillFilter::Filter pointing at its own default table (will_filter_filters) while the
        # dummy application's schema -- like production's -- has wf_filters.  The effect was that
        # no filter could be instantiated under test at all, so none of them were testable.
        config.table_name_prefix = 'wf'
      end

      # will_filter's own engine includes this into ::ApplicationRecord -- the *host
      # application's* base class, which Platform's models do not inherit from: they descend from
      # Platform::ApplicationRecord, which is an ActiveRecord::Base of its own.  So Model.filter,
      # which every admin screen in this gem calls, was never defined on any Platform model and
      # raised NoMethodError.
      Platform::ApplicationRecord.include(WillFilter::Concerns::WillFilterMethods)
    end

  end
end
