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

    # The admin, for Platform::Admin::BaseController#validate_admin.  ::User#admin? in the dummy
    # application is a name check, so the name is the whole of what makes this user an admin.
    def admin_user
      @admin_user ||= create_user('Admin')
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

      # Platform::Config keeps the current user in a thread local, and the test runner reuses the
      # thread -- so without this a test sees whoever the test before it logged in as.  It does
      # not show up in a Platform::BaseController test, because :init_platform overwrites the
      # thread local from the session on every request; Platform::Api::BaseController has no such
      # callback, and that is where the leak was visible.
      Platform::Config.reset!
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

    # What the action assigned for its view.  #assigns itself moved out of Rails into the
    # rails-controller-testing gem, which this suite does not carry; the controller's view assigns
    # are the same hash it used to read.
    def assigned(name)
      @controller.view_assigns[name.to_s]
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

# Test-only routes.
#
# config/routes.rb routes a dozen actions; the engine has twenty-six controllers.  The Rails 2
# `map.connect "/platform/#{ctrl}/:action"` lines that used to reach the rest are still sitting
# commented out at the bottom of that file, so most of these actions are currently unreachable in
# a host application too -- but ActionController::TestCase needs a route to generate a URL for
# the action under test, and a controller with no route is exactly the controller whose Rails 8
# breakage nobody has noticed.  Tests are where that gets found.
#
# Drawn here rather than in config/routes.rb on purpose: publishing admin endpoints is a decision
# about the gem's surface, not about its test suite, and nothing here should change what a host
# application exposes.
#
# `disable_clear_and_finalize` makes #draw append instead of replacing, so config/routes.rb's own
# routes survive -- and because these come last, none of them can shadow a real route.  URL
# generation picks the first route that fits, which is still the real one wherever there is one.
#
# The load has to be forced before that, below.  Routes are lazy in Rails 8, so #draw would
# otherwise trigger the reload itself -- and Rails::Application::RoutesReloader#revert hands
# `disable_clear_and_finalize` back to false on its way out, which would leave #draw clearing the
# very routes it had just loaded.
module Platform
  TEST_ONLY_ROUTES = {
    'admin/apps'            => %w[view tokens users scopes lb_scope delete_scope ratings block
                                  unblock approve reject set_permission remove_permission lb_edit
                                  update],
    'admin/categories'      => %w[index tree items lb_update_category update_category
                                  lb_update_application_category update_application_category
                                  delete_category assign_category category_assigner
                                  category_assigner_tree update_featured_flag],
    'admin/clientsdk'       => %w[index],
    'admin/developers'      => %w[index view lb_edit update],
    'admin/forum'           => %w[index messages],
    'admin/metrics'         => %w[index usage application_log rollup_log],
    'api/apps'              => %w[index],
    'apps'                  => %w[paginate_module],
    'developer/api_explorer'=> %w[index history options oauth_lander],
    'developer/apps'        => %w[create_version version reset_secret submit lb_scopes],
    'developer/blog'        => %w[index],
    'developer/dashboard'   => %w[settings update_section],
    'developer/forum'       => %w[index topic delete_topic delete_message],
    # rate_limits, scopes, terms, widget_doc and widget_tree have no method on the controller:
    # they are templates with no action, which Rails renders anyway.  They are routed here
    # because _navigation links to them, so without a route every help page fails to render.
    'developer/help'        => %w[index reference branding oauth_intro oauth_server_side
                                  oauth_client_side oauth_trusted_client oauth_app_login
                                  oauth_desktop oauth_mobile oauth_extensions sdk_js sdk_ios api
                                  rate_limits scopes terms widget_doc widget_tree],
    'developer/info'        => %w[index update_section],
    'developer/registration'=> %w[index proceed],
    'developer/resources'   => %w[index],
    'forum'                 => %w[new_message delete_topic delete_message],
    'oauth'                 => %w[auth_success auth_failed deauthorize logout revoke status token xd],
    'ratings'               => %w[submit_app_rating delete_app_rating],
  }.freeze
end

Rails.application.reload_routes_unless_loaded

Platform::Engine.routes.disable_clear_and_finalize = true
Platform::Engine.routes.draw do
  Platform::TEST_ONLY_ROUTES.each do |controller, actions|
    actions.each do |action|
      match "/#{controller}/#{action}(/:id)", to: "#{controller}##{action}", via: :all
    end
  end
end
Platform::Engine.routes.disable_clear_and_finalize = false
Platform::Engine.routes.finalize!

# Load fixtures from the engine
if ActiveSupport::TestCase.respond_to?(:fixture_paths=)
  ActiveSupport::TestCase.fixture_paths = [ File.expand_path("fixtures", __dir__) ]
  ActionDispatch::IntegrationTest.fixture_paths = ActiveSupport::TestCase.fixture_paths
  ActiveSupport::TestCase.file_fixture_path = File.expand_path("fixtures", __dir__) + "/files"
  ActiveSupport::TestCase.fixtures :all
end
