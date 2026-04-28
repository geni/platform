# Skip preinitializer for Rails 3.0+ - it has built-in Bundler support
# Only run this for Rails 2.3
if ENV['BUNDLE_GEMFILE'] && !ENV['BUNDLE_GEMFILE'].include?('.next')
  begin
    require 'rubygems'
    require 'bundler'
  rescue LoadError
    raise "Could not load the bundler gem. Install it with `gem install bundler`."
  end

  if Gem::Version.new(Bundler::VERSION) <= Gem::Version.new("0.9.24")
    raise RuntimeError, "Your bundler version is too old for Rails 2.3.\n" +
     "Run `gem install bundler` to upgrade."
  end

  begin
    # Set up load paths for all bundled gems
    # Don't override BUNDLE_GEMFILE if it's already set (for dual-boot)
    ENV["BUNDLE_GEMFILE"] ||= File.expand_path("../../Gemfile", __FILE__)
    Bundler.setup
  rescue Bundler::GemNotFound
    raise RuntimeError, "Bundler couldn't find some gems.\n" +
      "Did you run `bundle install`?"
  end
end
