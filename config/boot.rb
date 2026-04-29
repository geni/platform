# Don't change this file!
# Configure your app in config/environment.rb and config/environments/*.rb

# For Rails 3.0+ with Bundler, skip the custom boot process
# Rails 3.0+ loads through application.rb via Bundler
RAILS_ROOT = "#{File.dirname(__FILE__)}/.." unless defined?(RAILS_ROOT)

# Check if we're running Rails 3.0+
require 'rubygems'
require 'bundler/setup' if File.exist?("#{RAILS_ROOT}/Gemfile")

# Apply Ruby 2.7 compatibility patches for Rails 3.0-3.1 BEFORE loading Rails
# Fix BigDecimal.yaml_as (removed in Ruby 2.7+)
require 'bigdecimal'
BigDecimal.singleton_class.class_eval do
  unless respond_to?(:yaml_as)
    define_method(:yaml_as) do |tag|
      # No-op for Ruby 2.7+ where yaml_as was removed
    end
  end
end

# Fix TimeZone#parse circular argument reference in Rails 3.0-3.1
if defined?(Gem)
  gem_spec = Gem.loaded_specs.values.find { |spec| spec.name == 'activesupport' && spec.version.to_s =~ /^3\.[01]\./ }
  if gem_spec
    timezone_file = File.join(gem_spec.full_gem_path, 'lib/active_support/values/time_zone.rb')
    if File.exist?(timezone_file) && File.writable?(timezone_file)
      content = File.read(timezone_file)
      if content.include?('def parse(str, now=now)')
        content.gsub!(/def parse\(str, now=now\)/, "def parse(str, now=nil)\n      now ||= self.now")
        File.write(timezone_file, content)
      end
    end
  end

  # Fix asset_tag_helper nil relative_url_root issue in Rails 3.0
  actionpack_spec = Gem.loaded_specs.values.find { |spec| spec.name == 'actionpack' && spec.version.to_s =~ /^3\.0\./ }
  if actionpack_spec
    asset_helper_file = File.join(actionpack_spec.full_gem_path, 'lib/action_view/helpers/asset_tag_helper.rb')
    if File.exist?(asset_helper_file) && File.writable?(asset_helper_file)
      content = File.read(asset_helper_file)
      # Patch compute_public_path to handle nil relative_url_root
      if content.include?('!source.start_with?(controller.config.relative_url_root)') && !content.include?('# PATCHED FOR NIL')
        content.gsub!(
          '!source.start_with?(controller.config.relative_url_root)',
          '!source.start_with?(controller.config.relative_url_root || "") # PATCHED FOR NIL'
        )
        File.write(asset_helper_file, content)
      end
    end
  end

  # Fix Rails 3.1 route_set frozen string issue (Ruby 2.7+)
  actionpack_31_spec = Gem.loaded_specs.values.find { |spec| spec.name == 'actionpack' && spec.version.to_s =~ /^3\.1\./ }
  if actionpack_31_spec
    route_set_file = File.join(actionpack_31_spec.full_gem_path, 'lib/action_dispatch/routing/route_set.rb')
    if File.exist?(route_set_file) && File.writable?(route_set_file)
      content = File.read(route_set_file)
      # Patch to ensure path is not frozen
      if content.include?('path = (script_name.blank? ? _generate_prefix(options) : script_name.chomp(\'/\')).to_s') && !content.include?('# PATCHED FOR FROZEN')
        content.gsub!(
          'path = (script_name.blank? ? _generate_prefix(options) : script_name.chomp(\'/\')).to_s',
          'path = (script_name.blank? ? _generate_prefix(options) : script_name.chomp(\'/\')).to_s.dup # PATCHED FOR FROZEN'
        )
        File.write(route_set_file, content)
      end
    end
  end
end

# Fix ActiveRecord 3.1 has_many_association circular argument reference
if defined?(Gem)
  # Try vendored gem first, then system gem
  ar_spec = Gem.loaded_specs.values.select { |spec| spec.name == 'activerecord' && spec.version.to_s =~ /^3\.1\./ }
                              .sort_by { |spec| spec.full_gem_path.include?('vendor/bundle') ? 0 : 1 }
                              .first
  if ar_spec
    has_many_file = File.join(ar_spec.full_gem_path, 'lib/active_record/associations/has_many_association.rb')
    if File.exist?(has_many_file) && File.writable?(has_many_file)
      content = File.read(has_many_file)
      if content.include?('reflection = reflection') && !content.include?('# PATCHED FOR CIRCULAR')
        # Fix circular argument reference for all methods
        content.gsub!(/def (has_cached_counter\?|cached_counter_attribute_name|inverse_updates_counter_cache\?)\(reflection = reflection\)/) do |match|
          "def #{$1}(reflection = nil) # PATCHED FOR CIRCULAR\n        reflection ||= self.reflection"
        end
        # Fix update_counter which has an additional parameter
        content.gsub!(/def update_counter\(difference, reflection = reflection\)/) do |match|
          "def update_counter(difference, reflection = nil) # PATCHED FOR CIRCULAR\n        reflection ||= self.reflection"
        end
        File.write(has_many_file, content)
      end
    end
  end
end

# Fix test-unit 3.5.7-3.6.x local_name bug with nested test suites
# The testrunner tries to call local_name on TestSuite objects but the method doesn't exist
if defined?(Gem)
  test_unit_spec = Gem.loaded_specs.values.find { |spec| spec.name == 'test-unit' && spec.version.to_s =~ /^3\.[56]\./ }
  if test_unit_spec
    testsuite_file = File.join(test_unit_spec.full_gem_path, 'lib/test/unit/testsuite.rb')
    if File.exist?(testsuite_file) && File.writable?(testsuite_file)
      content = File.read(testsuite_file)
      # Add local_name method to TestSuite class if not already patched
      if !content.include?('# PATCHED: local_name method') && content.include?('class TestSuite')
        # Find the private keyword or the end of the class, and insert before it
        # Look for "private" keyword first
        insertion_point = content.index(/^      private$/m)
        if insertion_point
          method_code = <<-RUBY
      # PATCHED: local_name method for test-unit 3.5.7-3.6.x compatibility
      # Returns the suite name for reporting purposes
      def local_name
        @name || name.to_s
      end

RUBY
          content.insert(insertion_point, method_code)
          File.write(testsuite_file, content)
        end
      end
    end
  end
end

# Skip the rest of boot process for Rails 3.0+ - it's handled by application.rb
return if defined?(Bundler)

