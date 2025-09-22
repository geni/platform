require 'mocha/minitest'
require 'pp'

ENV["RAILS_ENV"] = "test"

# This has to happen before other files are loaded
unless defined?($SKIP_COVERAGE)
  require 'simplecov'
  SimpleCov.start do
    add_filter 'config'
    add_filter 'test'
    add_filter 'vendor'
  end
end

require_relative "../test/dummy/config/environment"

class ActiveSupport::TestCase

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
    session[:_csrf_token] ||= ActiveSupport::SecureRandom.base64(32)
  end
end

class Object

  def tap_pp(*args)
    pp [*args, self]
    self
  end

end # class Object

Tr8n::Config.config[:enable_tr8n] = false

ActiveRecord::Migrator.migrations_paths = [ File.expand_path("../test/dummy/db/migrate", __dir__) ]
ActiveRecord::Migrator.migrations_paths << File.expand_path("../db/migrate", __dir__)
require "rails/test_help"

# Load fixtures from the engine
if ActiveSupport::TestCase.respond_to?(:fixture_paths=)
  ActiveSupport::TestCase.fixture_paths = [ File.expand_path("fixtures", __dir__) ]
  ActionDispatch::IntegrationTest.fixture_paths = ActiveSupport::TestCase.fixture_paths
  ActiveSupport::TestCase.file_fixture_path = File.expand_path("fixtures", __dir__) + "/files"
  ActiveSupport::TestCase.fixtures :all
end
