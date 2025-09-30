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

module Platform
  # Including this in an ActionDispatch::IntegrationTest won't work
  # because ActionDispatch::IntegrationTest has an app method.
  module TestMixins

  private

    def app(params={})
      @app ||= begin
        params[:callback_url]   ||= 'http://localhost'
        params[:contact_email]  ||= 'dev@geni.com'
        params[:developer]      ||= developer
        params[:name]           ||= 'TestApp'
        params[:url]            ||= 'http://localhost'
        Platform::Application.create!(params)
      end
    end

    def user
      @user ||= ::User.create!(:name => 'user name')
    end

    def developer(user=nil)
      return Platform::Developer::Developer.find_or_create_by(:user => user) unless user.nil?

      @developer ||= begin
        user = ::User.create!(:name => 'Developer')
        Platform::Developer::Developer.find_or_create_by(:user => user)
      end
    end

  end # module TestMixins

  class TestCase < ActiveSupport::TestCase
    include Platform::TestMixins
  end # class TestCase

  class ControllerTestCase < ActionController::TestCase
    include Platform::Engine.routes.url_helpers
    include Platform::TestMixins

    def setup
      @routes = Platform::Engine.routes
    end

  private

    def login_as(user)
      user = user.user if user.is_a?(Platform::Developer::Developer)
      @request.session[:user_id] = user.id
    end

    def logout
      @request.session[:user_id] = nil
    end

    def form_authenticity_token
      @controller.send(:form_authenticity_token)
    end

  end # ControllerTest
end # module Platform

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
