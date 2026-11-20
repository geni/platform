# Don't change this file!
# Configure your app in config/environment.rb and config/environments/*.rb

# Rails 3.0 boots from config/application.rb, so there is no boot process to run here -- only the
# Ruby 2.7 compatibility patches, which have to land before Rails is loaded.
#
# This file used to carry a second boot path for Rails 2.3, selected by whether BUNDLE_GEMFILE
# named a ".next" Gemfile: the whole Rails::Initializer / GemBoot / VendorBoot apparatus below the
# gate, plus `Rails.boot!` at the end.  That is gone with the dual boot.  Nothing on this branch is
# Rails 2.3, and a boot file that picks its Rails from an environment variable means the branch name
# does not tell you what you are running.

RAILS_ROOT = "#{File.dirname(__FILE__)}/.." unless defined?(RAILS_ROOT)

require 'rubygems'

# BigDecimal.yaml_as was removed in Ruby 2.7, and Rails 3.0's activesupport calls it while loading.
require 'bigdecimal'
BigDecimal.singleton_class.class_eval do
  unless respond_to?(:yaml_as)
    define_method(:yaml_as) do |tag|
      # No-op for Ruby 2.7+ where yaml_as was removed
    end
  end
end

# activesupport 3.0's TimeZone#parse is `def parse(str, now=now)`, a circular argument reference
# that Ruby 2.7 rejects outright as a syntax error -- so it has to be rewritten in the installed gem
# before anything requires it.  Idempotent: the gsub only matches the unpatched form.
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
