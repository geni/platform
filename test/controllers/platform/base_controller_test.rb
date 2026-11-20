require 'test_helper'

# What every Platform controller inherits.  Driven through Platform::HomeController because it is
# the one subclass that skips :validate_guest_user, so a guest reaches the action and the
# guest-facing accessors can be read as a guest sees them.
#
# The before_actions themselves -- :init_platform, :validate_platform_enabled,
# :validate_guest_user -- are covered in test/controllers/platform/home_controller_test.rb, and
# #redirect_to_source in test/controllers/platform/forum_controller_test.rb, which is where it is
# actually used.
class Platform::BaseControllerTest < Platform::ControllerTestCase
  tests Platform::HomeController

  ##########################################################################
  #### The accessors the views ask for
  ##########################################################################

  test 'the viewer accessors answer for a logged in user' do
    login_as user
    get :index

    assert_equal user, @controller.platform_current_user
    assert_not @controller.platform_current_user_is_guest?
    assert_not @controller.platform_current_user_is_admin?
    assert_not @controller.platform_current_user_is_developer?
    assert_nil @controller.platform_current_developer
  end

  test 'the viewer accessors answer for a guest' do
    get :index

    assert @controller.platform_current_user_is_guest?
    assert_not @controller.platform_current_user_is_developer?
  end

  test 'the viewer accessors answer for an admin' do
    login_as admin_user
    get :index

    assert @controller.platform_current_user_is_admin?
  end

  test 'the viewer accessors answer for a developer' do
    login_as developer
    get :index

    assert @controller.platform_current_user_is_developer?
    assert_equal developer, @controller.platform_current_developer
  end

  # All five are helper_methods, because the layout and its partials read them.
  test 'the viewer accessors are available to the views' do
    %i[platform_current_user platform_current_developer platform_current_user_is_admin?
       platform_current_user_is_guest? platform_current_user_is_developer?
       mobile_device?].each do |name|
      assert_includes Platform::HomeController._helper_methods, name
    end
  end

  ##########################################################################
  #### mobile_device?
  ####
  #### Platform::OauthController#display reads this to choose the mobile consent template, so it
  #### decides what an iPhone sees when it authorizes an application.
  ##########################################################################

  test 'mobile_device? is false when the request says nothing' do
    get :index
    assert_equal false, @controller.mobile_device?
  end

  test 'mobile_device? recognises an iPhone and an Android' do
    ['iPhone', 'Mozilla/5.0 (Linux; Android 14)'].each do |agent|
      @request.user_agent = agent
      get :index
      assert_equal true, @controller.mobile_device?, "#{agent} should be a mobile device"
    end
  end

  test 'mobile_device? matches whatever the case' do
    @request.user_agent = 'SOMETHING IPHONE SOMETHING'
    get :index
    assert_equal true, @controller.mobile_device?
  end

  test 'mobile_device? is false for a desktop browser' do
    @request.user_agent = 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) Chrome/120'
    get :index
    assert_equal false, @controller.mobile_device?
  end

  ##########################################################################
  #### page / per_page
  ##########################################################################

  test 'page defaults to the first page' do
    get :index
    assert_equal 1, @controller.send(:page)
  end

  test 'page takes the page asked for' do
    get :index, params: {page: '3'}
    assert_equal 3, @controller.send(:page)
  end

  test 'a blank page falls back to the first page' do
    get :index, params: {page: ''}
    assert_equal 1, @controller.send(:page)
  end

  test 'per_page defaults to thirty' do
    get :index
    assert_equal 30, @controller.send(:per_page)
  end

  test 'per_page takes the size asked for' do
    get :index, params: {per_page: '5'}
    assert_equal 5, @controller.send(:per_page)
  end

  test 'a blank per_page falls back to the default' do
    get :index, params: {per_page: ''}
    assert_equal 30, @controller.send(:per_page)
  end

  ##########################################################################
  #### The host application's hooks
  ####
  #### Platform::Config.before_actions, .skip_before_actions, .after_actions and .helpers are read
  #### when the class is loaded, so they cannot be exercised from a test -- but they are the
  #### documented way a host application hangs its own callbacks on these controllers, and all
  #### four default to empty, so the class body's `if ... .any?` guards are what keep an
  #### unconfigured host working.
  ##########################################################################

  test 'the host application hooks default to empty' do
    assert_empty Platform::Config.before_actions
    assert_empty Platform::Config.skip_before_actions
    assert_empty Platform::Config.after_actions
    assert_empty Platform::Config.helpers
    assert_empty Platform::Config.admin_helpers
  end

  test 'BaseHelper is on every platform controller' do
    assert_includes Platform::HomeController._helpers.ancestors, Platform::BaseHelper
  end

  ##########################################################################
  #### platform_toggler_tag
  ####
  #### Driven through the real view context rather than in isolation, because what was wrong with
  #### it was precisely how its result met ERB: the method built a String and handed it back, so
  #### the whole thing was escaped and every collapsible section on every admin, developer and
  #### documentation page rendered its own markup as visible text.
  ##########################################################################

  test 'the toggler renders both spans as markup' do
    assert_select_in toggler('basic_info'), 'span#basic_info_open'
    assert_select_in toggler('basic_info'), 'span#basic_info_closed'
  end

  test 'the toggler is marked safe, so ERB does not escape it' do
    assert_predicate toggler('basic_info'), :html_safe?
    assert_no_match '&lt;span', toggler('basic_info')
  end

  # link_to_function is link_to, which escapes the text it is given -- so the entity reached the
  # page as "&amp;#x25BC;" and showed as literal "&#x25BC;" rather than an arrow.
  test 'the toggler arrows are entities rather than escaped text' do
    html = toggler('basic_info')

    assert_match '&#x25BC;', html
    assert_match '&#x25BA;', html
    assert_no_match '&amp;#x25BC;', html
  end

  # Open means the expanded arrow is showing and the collapsed one is hidden, and the other way
  # round when closed.  Platform.Effects.toggle swaps them.
  test 'the toggler hides the collapsed arrow when open' do
    html = toggler('basic_info', '', true)

    assert_select_in html, 'span#basic_info_open:not([style])'
    assert_select_in html, 'span#basic_info_closed[style=?]', 'display:none'
  end

  test 'the toggler hides the expanded arrow when closed' do
    html = toggler('basic_info', '', false)

    assert_select_in html, 'span#basic_info_open[style=?]', 'display:none'
    assert_select_in html, 'span#basic_info_closed:not([style])'
  end

  test 'the toggler wires both arrows to the same toggle call' do
    html = toggler('basic_info')

    assert_select_in html, 'a[onclick*=?]',
                     "Platform.Effects.toggle('basic_info_open','basic_info_closed','basic_info')",
                     count: 2
  end

  test 'the toggler labels the arrows when asked to' do
    assert_match 'A section', toggler('basic_info', 'A section')
  end

  # Both used to be interpolated into markup raw.  That was invisible while the result was being
  # escaped wholesale; marking it safe is what makes it matter.
  test 'the toggler escapes the label' do
    html = toggler('basic_info', '<script>alert(1)</script>')

    assert_no_match '<script>', html
    assert_match '&lt;script&gt;', html
  end

  test 'the toggler escapes the content id' do
    html = toggler('"><script>alert(1)</script>')

    assert_no_match '<script>', html
  end

private

  def toggler(*args)
    login_as user
    get :index

    @controller.view_context.platform_toggler_tag(*args)
  end

  # assert_select against a fragment rather than the last response.
  def assert_select_in(html, *args, &block)
    assert_select Nokogiri::HTML::DocumentFragment.parse(html), *args, &block
  end

end # class Platform::BaseControllerTest
