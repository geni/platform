require 'test_helper'

class Platform::ConfigTest < Platform::TestCase

  ##########################################################################
  #### site_host and site_url
  ####
  #### These replaced two bare constants -- SITE and DEFAULT_SITE_LINK -- that
  #### Platform::Application#admin_link, #app_url and the widget_doc help page interpolated and
  #### that the gem never defined anywhere.  They came from the host application's own top-level
  #### namespace, so on any host without them those three call sites raised NameError.
  ##########################################################################

  test 'site_host is the configured bare hostname' do
    assert_equal 'www.example.com', Platform::Config.site_host
  end

  test 'site_host reads the host key rather than a hardcoded value' do
    with_site_info(host: 'other.example.com') do
      assert_equal 'other.example.com', Platform::Config.site_host
    end
  end

  # #config reads the *host application's* config/platform/config.yml rather than merging with
  # the gem's, so a host that has not copied the new `host:` key in would get nil -- and
  # #site_url would build "https://".  The fallback is #site_base_url, which the developer help
  # pages and Platform::OauthHardening's host check already treat as this same hostname.
  test 'site_host falls back to site_base_url when the host key is absent' do
    Platform::Config.stubs(:site_base_url).returns('legacy.example.com')

    with_site_info(host: nil) do
      assert_equal 'legacy.example.com', Platform::Config.site_host
    end
  end

  test 'site_url is the scheme and host with no trailing slash' do
    assert_equal 'https://www.example.com', Platform::Config.site_url
  end

  test 'site_url follows site_host' do
    Platform::Config.stubs(:site_host).returns('other.example.com')

    assert_equal 'https://other.example.com', Platform::Config.site_url
  end

  test 'site_url takes an explicit protocol' do
    assert_equal 'http://www.example.com', Platform::Config.site_url('http')
  end

  ##########################################################################
  #### default_protocol
  ####
  #### http only in development.  Platform::Application#oauth_url had this expression inline and
  #### now shares it, so the two cannot drift.
  ##########################################################################

  test 'default_protocol is https outside development' do
    assert_equal 'test', Platform::Config.env.to_s
    assert_equal 'https', Platform::Config.default_protocol
  end

  test 'default_protocol is http in development' do
    Platform::Config.stubs(:env).returns('development')

    assert_equal 'http', Platform::Config.default_protocol
  end

  test 'default_protocol is https in production' do
    Platform::Config.stubs(:env).returns('production')

    assert_equal 'https', Platform::Config.default_protocol
  end

  # Rails.env is a StringInquirer rather than a String, so the comparison has to survive that.
  test 'default_protocol copes with a StringInquirer env' do
    Platform::Config.stubs(:env).returns(ActiveSupport::StringInquirer.new('development'))

    assert_equal 'http', Platform::Config.default_protocol
  end

  ##########################################################################
  #### site_base_url
  ####
  #### Left as found, but worth pinning: it is defined twice in config.rb and the second
  #### definition -- api[:base_url] -- shadows the first, so site_info[:base_url] is dead
  #### configuration.  #site_host is what new code should read.
  ##########################################################################

  test 'site_base_url resolves to the API base url, not site_info' do
    assert_equal Platform::Config.api[:base_url], Platform::Config.site_base_url
    assert_equal Platform::Config.api_base_url,   Platform::Config.site_base_url
  end

  test 'site_info carries no base_url for the shadowed definition to have read' do
    assert_nil Platform::Config.site_info[:base_url]
  end

private

  # Platform::Config.config is memoized on the class, so a test that needs different site_info
  # has to swap the memo and put it back.
  def with_site_info(overrides)
    original = Platform::Config.config
    swapped  = original.deep_dup
    overrides.each { |key, value| swapped[:site_info][key] = value }

    Platform::Config.instance_variable_set(:@config, swapped)
    yield
  ensure
    Platform::Config.instance_variable_set(:@config, original)
  end

end # class Platform::ConfigTest
