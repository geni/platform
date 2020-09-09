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

require_relative '../config/environment'
require 'test_help'

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
  self.use_transactional_fixtures = true

  # Instantiated fixtures are slow, but give you @david where otherwise you
  # would need people(:david).  If you don't want to migrate your existing
  # test cases which use the @david style and don't mind the speed hit (each
  # instantiated fixtures translates to a database query per test method),
  # then set this back to true.
  self.use_instantiated_fixtures  = false

  # Setup all fixtures in test/fixtures/*.(yml|csv) for all tests in alphabetical order.
  #
  # Note: You'll currently still have to declare fixtures explicitly in integration tests
  # -- they do not yet inherit this setting
  fixtures :all

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

  def developer(user)
    Platform::Developer.find_or_create(user)
  end

  def login_as(user)
    @request.session[:platform_user_id] = user.id
  end

  def logout
    @request.session[:platform_user_id] = nil
  end
end

Tr8n::Config.config[:enable_tr8n] = false
