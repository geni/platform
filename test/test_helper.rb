require 'mocha/minitest'
require 'pp'
require 'tmpdir'

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

    # The test's application.  Memoized, so every call in one test is the same record -- which is
    # what most tests want, and what the tests written before #create_app existed rely on.  Pass
    # params only on the first call; later calls ignore them.
    def app(params={})
      @app ||= create_app(params)
    end

    # An additional application, for the tests that need two of them.  Takes the same defaults as
    # #app and is not memoized, so each call is a distinct record.
    #
    # A key given explicitly wins even when its value is nil or blank, which the registered
    # callback and origin tests depend on: "an application with no callback_url" is a case with
    # its own behaviour, and `||=` would have quietly filled the default back in.
    def create_app(params={})
      {
        callback_url: 'http://localhost',
        contact_email: 'dev@example.com',
        name: 'TestApp',
        url: 'http://localhost',
      }.each { |key, value| params[key] = value unless params.key?(key) }

      params[:developer] = developer unless params.key?(:developer)

      Platform::Application.create!(params)
    end

    def user
      @user ||= create_user
    end

    # An additional user.  Not memoized; #user is the memoized one.  The name matters in a couple
    # of places -- ::User#guest? and #admin? in the dummy application are name checks -- so it is
    # a parameter rather than a constant.
    def create_user(name='user name')
      ::User.create!(name: name)
    end

    def developer(user=nil)
      return Platform::Developer::Developer.find_or_create_by(user: user) unless user.nil?

      @developer ||= begin
        user = ::User.create!(name: 'Developer')
        Platform::Developer::Developer.find_or_create_by(user: user)
      end
    end

    # A throwaway media root for the tests that exercise Platform::Media::Media#write, which
    # really does resize and write a file.  Without this they would litter the dummy
    # application's public directory, since Platform::Config.media_path points there.
    def with_tmp_media_path
      dir = Dir.mktmpdir('platform-media')
      Platform::Config.stubs(:media_path).returns(dir)
      yield dir
    ensure
      FileUtils.remove_entry(dir) if dir && File.exist?(dir)
    end

    # The image the media tests resize.  512x512, so a resize is visible.
    def fixture_image
      File.new(Rails.root.join('public', 'icon.png'))
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
