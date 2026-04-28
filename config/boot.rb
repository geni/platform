# Don't change this file!
# Configure your app in config/environment.rb and config/environments/*.rb

# For Rails 3.0+ with Bundler, skip the custom boot process but load Rails
if ENV['BUNDLE_GEMFILE'] && ENV['BUNDLE_GEMFILE'].include?('.next')
  RAILS_ROOT = "#{File.dirname(__FILE__)}/.." unless defined?(RAILS_ROOT)

  # Patch Rails 3.0 for Ruby 2.7+ BEFORE loading Rails
  require 'rubygems'

  # Fix BigDecimal.yaml_as (removed in Ruby 2.7+)
  require 'bigdecimal'
  BigDecimal.singleton_class.class_eval do
    unless respond_to?(:yaml_as)
      define_method(:yaml_as) do |tag|
        # No-op for Ruby 2.7+ where yaml_as was removed
      end
    end
  end

  # Fix TimeZone#parse circular argument reference
  gem_spec = Gem.loaded_specs.values.find { |spec| spec.name == 'activesupport' && spec.version.to_s.start_with?('3.0.') }
  if gem_spec
    timezone_file = File.join(gem_spec.full_gem_path, 'lib/active_support/values/time_zone.rb')
    if File.exist?(timezone_file)
      content = File.read(timezone_file)
      if content.include?('def parse(str, now=now)')
        content.gsub!(/def parse\(str, now=now\)/, "def parse(str, now=nil)\n      now ||= self.now")
        File.write(timezone_file, content)
      end
    end
  end

  # Skip boot process for Rails 3.0 - it's handled by application.rb
  return
end

RAILS_ROOT = "#{File.dirname(__FILE__)}/.." unless defined?(RAILS_ROOT)

module Rails
  class << self
    def boot!
      unless booted?
        preinitialize
        pick_boot.run
      end
    end

    def booted?
      defined? Rails::Initializer
    end

    def pick_boot
      (vendor_rails? ? VendorBoot : GemBoot).new
    end

    def vendor_rails?
      File.exist?("#{RAILS_ROOT}/vendor/rails")
    end

    def preinitialize
      load(preinitializer_path) if File.exist?(preinitializer_path)
    end

    def preinitializer_path
      "#{RAILS_ROOT}/config/preinitializer.rb"
    end
  end

  class Boot
    def run
      load_initializer
    end
  end

  class VendorBoot < Boot
    def load_initializer
      require "#{RAILS_ROOT}/vendor/rails/railties/lib/initializer"
      Rails::Initializer.run(:install_gem_spec_stubs)
      Rails::GemDependency.add_frozen_gem_path
    end
  end

  class GemBoot < Boot
    def load_initializer
      self.class.load_rubygems
      load_rails_gem

      # Apply Ruby 2.7 compatibility patches BEFORE loading Rails
      patch_bigdecimal_for_ruby_27
      patch_rails_30_for_ruby_27

      # Rails 3.0 uses 'rails', Rails 2.3 uses 'initializer'
      begin
        require 'rails'
      rescue LoadError
        require 'initializer'
      end

      # Load additional Ruby 2.7 compatibility patches for Rails 3.0 after rails loads
      rails_30_compat = File.expand_path('../../lib/core_ext/rails_30_ruby_27_compat', __FILE__)
      require rails_30_compat if File.exist?("#{rails_30_compat}.rb")
    end

    def patch_bigdecimal_for_ruby_27
      # Fix BigDecimal.yaml_as doesn't exist in newer Psych (Ruby 2.7+)
      # This MUST be done before requiring rails/activesupport
      require 'bigdecimal'
      BigDecimal.singleton_class.class_eval do
        unless respond_to?(:yaml_as)
          define_method(:yaml_as) do |tag|
            # No-op for Ruby 2.7+ where yaml_as was removed
          end
        end
      end
    end

    def patch_rails_30_for_ruby_27
      # Find Rails 3.0 activesupport gem
      if defined?(Gem)
        gem_spec = Gem.loaded_specs.values.find { |spec| spec.name == 'activesupport' && spec.version.to_s.start_with?('3.0.') }
        return unless gem_spec

        timezone_file = File.join(gem_spec.full_gem_path, 'lib/active_support/values/time_zone.rb')
        return unless File.exist?(timezone_file)

        content = File.read(timezone_file)

        # Fix: def parse(str, now=now) - circular argument reference (syntax error in Ruby 2.7+)
        if content.include?('def parse(str, now=now)')
          content.gsub!(/def parse\(str, now=now\)/, "def parse(str, now=nil)\n      now ||= self.now")
          File.write(timezone_file, content)
        end
      end
    end

    def load_rails_gem
      # Skip gem activation for Rails 3.0+ when using Bundler - it's already set up
      # Only needed for Rails 2.3 without Bundler
      return if ENV['BUNDLE_GEMFILE'] && ENV['BUNDLE_GEMFILE'].include?('.next')

      if version = self.class.gem_version
        gem 'rails', version
      else
        gem 'rails'
      end
    rescue Gem::LoadError => load_error
      if load_error.message =~ /Could not find RubyGem rails/
        STDERR.puts %(Missing the Rails #{version} gem. Please `gem install -v=#{version} rails`, update your RAILS_GEM_VERSION setting in config/environment.rb for the Rails version you do have installed, or comment out RAILS_GEM_VERSION to use the latest version installed.)
        exit 1
      else
        raise
      end
    end

    class << self
      def rubygems_version
        Gem::RubyGemsVersion rescue nil
      end

      def gem_version
        if defined? RAILS_GEM_VERSION
          RAILS_GEM_VERSION
        elsif ENV.include?('RAILS_GEM_VERSION')
          ENV['RAILS_GEM_VERSION']
        else
          parse_gem_version(read_environment_rb)
        end
      end

      def load_rubygems
        min_version = '1.3.2'
        require 'rubygems'
        unless rubygems_version >= min_version
          $stderr.puts %Q(Rails requires RubyGems >= #{min_version} (you have #{rubygems_version}). Please `gem update --system` and try again.)
          exit 1
        end

      rescue LoadError
        $stderr.puts %Q(Rails requires RubyGems >= #{min_version}. Please install RubyGems and try again: http://rubygems.rubyforge.org)
        exit 1
      end

      def parse_gem_version(text)
        $1 if text =~ /^[^#]*RAILS_GEM_VERSION\s*=\s*["']([!~<>=]*\s*[\d.]+)["']/
      end

      private
        def read_environment_rb
          File.read("#{RAILS_ROOT}/config/environment.rb")
        end
    end
  end
end

# Override Rails::Boot#run for Rails 2.3 Bundler integration
# Rails 3.0+ has built-in Bundler support, so only apply this for Rails 2.3
unless ENV['BUNDLE_GEMFILE'] && ENV['BUNDLE_GEMFILE'].include?('.next')
  class Rails::Boot
    def run
      load_initializer

      Rails::Initializer.class_eval do
        def load_gems
          @bundler_loaded ||= Bundler.require :default, Rails.env
        end
      end

      Rails::Initializer.run(:set_load_path)
    end
  end
end


# All that for this:
Rails.boot!
