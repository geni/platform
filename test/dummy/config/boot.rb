require 'rubygems'
gemfile = File.expand_path('../../../../Gemfile', __FILE__)

if File.exist?(gemfile)
  ENV['BUNDLE_GEMFILE'] = gemfile
  require 'bundler'
  Bundler.setup
end

# Apply Ruby 2.7 compatibility patches for Rails 3.2 BEFORE loading Rails
# Fix BigDecimal.yaml_as (removed in Ruby 2.7+)
require 'bigdecimal'
BigDecimal.singleton_class.class_eval do
  unless respond_to?(:yaml_as)
    define_method(:yaml_as) do |tag|
      # No-op for Ruby 2.7+ where yaml_as was removed
    end
  end
end

# Fix BigDecimal.new (removed in Ruby 2.6+, used by Rails 3.2)
# Rails 3.2's activesupport/core_ext/object/duplicable.rb uses BigDecimal.new
if RUBY_VERSION >= '2.6.0' && !BigDecimal.respond_to?(:new)
  BigDecimal.singleton_class.class_eval do
    define_method(:new) do |*args, **kwargs|
      if kwargs.empty?
        BigDecimal(*args)
      else
        BigDecimal(*args, **kwargs)
      end
    end
  end
end

$:.unshift File.expand_path('../../../../lib', __FILE__)