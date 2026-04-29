# This has to happen before other files are loaded
begin
  require 'simplecov'
  SimpleCov.start do
    command_name 'Tests'

    load_profile 'bundler_filter'
    load_profile 'test_frameworks'

    # these files will be overwritten by
    # the including application
    add_filter %r{^/config|platform_user.rb|application_(controller|helper).rb}

    add_group   'Controllers',  'app/controllers'
    add_group   'Helpers',      'app/helpers'
    add_group   'Libs',         'lib'
    add_group   'Models',       'app/models'
  end
rescue LoadError
  # don't load SimpleCov
end

# Prevent bundler/setup from being required again for Rails 3.0+
# (we're already running under bundle exec)
$LOADED_FEATURES << 'bundler/setup.rb' unless $LOADED_FEATURES.include?('bundler/setup.rb')

# Load Rails environment
require_relative '../config/environment'

# Rails 3.0+ - manually load Rails components before platform code
require 'action_controller'
require 'action_view'
require 'active_record'

# Now load the platform gem
require File.expand_path('../../lib/platform', __FILE__)

# Load all platform lib files
Dir[File.expand_path('../../lib/platform/**/*.rb', __FILE__)].each { |f| require f }

# Set up autoload paths for models, controllers, helpers
app_path = File.expand_path('../..', __FILE__)
ActiveSupport::Dependencies.autoload_paths += [
  File.join(app_path, 'app', 'models'),
  File.join(app_path, 'app', 'controllers'),
  File.join(app_path, 'app', 'helpers')
]

require 'test/unit'
require 'active_support/test_case'

require 'pp'

class ActiveSupport::TestCase
  # Transactional fixtures accelerate your tests by wrapping each test method
  # in a transaction that's rolled back on completion.  This ensures that the
  # test database remains unchanged so your fixtures don't have to be reloaded
  # between every test method.  Fewer database queries means faster tests.
  #
  # Read Mike Clark's excellent walkthrough at
  #   http://clarkware.com/cgi/blosxom/2005/10/24#Rails10FastTesting
  #
  # Every Active Record database supports transactions except MyISAM tables
  # in MySQL.  Turn off transactional fixtures in this case; however, if you
  # don't care one way or the other, switching from MyISAM to InnoDB tables
  # is recommended.
  #
  # The only drawback to using transactional fixtures is when you actually
  # need to test transactions.  Since your test is bracketed by a transaction,
  # any transactions started in your code will be automatically rolled back.
  # Rails 3.0+ uses use_transactional_tests instead
  if respond_to?(:use_transactional_fixtures=)
    self.use_transactional_fixtures = true
  elsif respond_to?(:use_transactional_tests=)
    self.use_transactional_tests = true
  end

  # Instantiated fixtures are slow, but give you @david where otherwise you
  # would need people(:david).  If you don't want to migrate your existing
  # test cases which use the @david style and don't mind the speed hit (each
  # instantiated fixtures translates to a database query per test method),
  # then set this back to true.
  if respond_to?(:use_instantiated_fixtures=)
    self.use_instantiated_fixtures  = false
  end

  # Setup all fixtures in test/fixtures/*.(yml|csv) for all tests in alphabetical order.
  #
  # Note: You'll currently still have to declare fixtures explicitly in integration tests
  # -- they do not yet inherit this setting
  # Skip for Rails 3.0 if fixtures directory doesn't exist
  if respond_to?(:fixtures) && File.directory?(File.expand_path('../../test/fixtures', __FILE__))
    fixtures :all
  end

  # Add more helper methods to be used by all tests here...

private

  def app(params={})
    @app ||= begin
      params[:callback_url]   ||= 'http://localhost'
      params[:contact_email]  ||= 'dev@geni.com'
      params[:developer]      ||= developer(user)
      params[:name]           ||= 'TestApp'
      params[:url]            ||= 'http://localhost'
      Platform::Application.create!(params)
    end
  end


  def user
    @user ||= Platform::PlatformUser.create!(:name => 'user name')
  end

  def developer(user=nil)
    return Platform::Developer.find_or_create(user) unless user.nil?

    @developer ||= begin
      user = Platform::PlatformUser.create!(:name => 'Developer')
      Platform::Developer.find_or_create(user)
    end
  end

  def login_as(user)
    user = user.user if user.is_a?(Platform::Developer)
    @request.session[:platform_user_id] = user.id
  end

  def logout
    @request.session[:platform_user_id] = nil
  end

  def form_authenticity_token
    # Rails 3.2+ uses SecureRandom
    session[:_csrf_token] ||= SecureRandom.base64(32)
  end
end

class Object

  def tap_pp(*args)
    pp [*args, self]
    self
  end

end # class Object

# Rails 3.0 ActionController::TestCase needs @routes setup
if defined?(PlatformGem::Application) && defined?(ActionController::TestCase)
  class ActionController::TestCase
    setup do
      @routes = PlatformGem::Application.routes
    end
  end
end

# Configure Tr8n if available
if defined?(Tr8n)
  Tr8n::Config.config[:enable_tr8n] = false
end
