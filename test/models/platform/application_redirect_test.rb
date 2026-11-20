require 'test_helper'

module Platform
  # Everything an authorize request is allowed to send the user back to, or postMessage a token
  # to.  All of it is derived from what the developer registered on the application; nothing here
  # consults the request.
  class ApplicationRedirectTest < Platform::TestCase

    ##########################################################################
    #### registered_redirect_uris
    ##########################################################################

    test 'the registered callback is the only redirect target' do
      a = create_app(callback_url: 'https://app.example.com/cb', url: 'https://app.example.com')

      assert_equal ['https://app.example.com/cb'], a.registered_redirect_uris
    end

    # #url is deliberately not a redirect target even though the old host-only check fell back to
    # it: a marketing homepage is not a callback, and treating it as one let an application with a
    # blank callback_url accept any redirect_uri on that host.
    test 'the application url is not a redirect target' do
      a = create_app(callback_url: nil, url: 'https://app.example.com')

      assert_equal [], a.registered_redirect_uris
    end

    test 'a blank callback registers nothing' do
      assert_equal [], create_app(callback_url: '').registered_redirect_uris
      assert_equal [], create_app(callback_url: '   ').registered_redirect_uris
    end

    ##########################################################################
    #### redirect_uri_allowed?
    ####
    #### Matches on scheme, host, port and path; the query string is free.  RFC 6749 section
    #### 3.1.2 asks for an exact string match and the query string is the one piece of that we
    #### cannot insist on -- the FTDNA connector's callback carries a profile_id the host app
    #### rewrites per request.
    ##########################################################################

    test 'the registered callback is allowed' do
      a = create_app(callback_url: 'https://app.example.com/cb')

      assert_equal true, a.redirect_uri_allowed?('https://app.example.com/cb')
    end

    test 'a query string on the candidate is allowed' do
      a = create_app(callback_url: 'https://app.example.com/cb')

      assert_equal true, a.redirect_uri_allowed?('https://app.example.com/cb?profile_id=7&state=x')
    end

    test 'a registered query string does not have to be reproduced' do
      a = create_app(callback_url: 'https://app.example.com/cb?profile_id=1')

      assert_equal true, a.redirect_uri_allowed?('https://app.example.com/cb')
      assert_equal true, a.redirect_uri_allowed?('https://app.example.com/cb?profile_id=2')
    end

    # The downgrade this check exists to stop: a registered https callback must not be reachable
    # over http, because the token is in the redirect.
    test 'the scheme may not be downgraded' do
      a = create_app(callback_url: 'https://app.example.com/cb')

      assert_equal false, a.redirect_uri_allowed?('http://app.example.com/cb')
    end

    test 'another host is not allowed' do
      a = create_app(callback_url: 'https://app.example.com/cb')

      assert_equal false, a.redirect_uri_allowed?('https://evil.example.com/cb')
      assert_equal false, a.redirect_uri_allowed?('https://app.example.com.evil.com/cb')
    end

    test 'another path on the registered host is not allowed' do
      a = create_app(callback_url: 'https://app.example.com/cb')

      assert_equal false, a.redirect_uri_allowed?('https://app.example.com/open-redirect')
      assert_equal false, a.redirect_uri_allowed?('https://app.example.com/cb/deeper')
      assert_equal false, a.redirect_uri_allowed?('https://app.example.com/')
    end

    test 'another port is not allowed' do
      a = create_app(callback_url: 'https://app.example.com/cb')

      assert_equal false, a.redirect_uri_allowed?('https://app.example.com:8443/cb')
    end

    # Comparing parsed components rather than strings is what makes this hold: the default port
    # written out in full is the same target, and a userinfo section that makes a URL *look* like
    # the registered host is not.
    test 'the default port may be written out in full' do
      a = create_app(callback_url: 'https://app.example.com/cb')

      assert_equal true, a.redirect_uri_allowed?('https://app.example.com:443/cb')
    end

    test 'a userinfo section cannot smuggle another host past the check' do
      a = create_app(callback_url: 'https://app.example.com/cb')

      assert_equal false, a.redirect_uri_allowed?('https://app.example.com@evil.com/cb'),
                   'this parses with host evil.com'
      assert_equal false, a.redirect_uri_allowed?('https://app.example.com:x@evil.com/cb')
    end

    test 'a trailing slash is not a different callback' do
      assert_equal true, create_app(callback_url: 'https://app.example.com/cb').
                           redirect_uri_allowed?('https://app.example.com/cb/')
      assert_equal true, create_app(callback_url: 'https://app.example.com/cb/').
                           redirect_uri_allowed?('https://app.example.com/cb')
    end

    test 'an empty path and a bare slash are the same callback' do
      a = create_app(callback_url: 'https://app.example.com')

      assert_equal true, a.redirect_uri_allowed?('https://app.example.com/')
      assert_equal true, a.redirect_uri_allowed?('https://app.example.com')
    end

    test 'nothing is allowed when nothing is registered' do
      a = create_app(callback_url: nil, url: 'https://app.example.com')

      assert_equal false, a.redirect_uri_allowed?('https://app.example.com/cb'),
                   'no registered callback means no redirect target, not "anything goes"'
    end

    test 'an unparseable or schemeless candidate is not allowed' do
      a = create_app(callback_url: 'https://app.example.com/cb')

      assert_equal false, a.redirect_uri_allowed?(nil)
      assert_equal false, a.redirect_uri_allowed?('')
      assert_equal false, a.redirect_uri_allowed?('/cb')
      assert_equal false, a.redirect_uri_allowed?('app.example.com/cb')
      assert_equal false, a.redirect_uri_allowed?('http://')
      assert_equal false, a.redirect_uri_allowed?('::::')
    end

    ##########################################################################
    #### redirect_uri_legacy_allowed?
    ####
    #### The check that was in force before #redirect_uri_allowed? existed: hosts only, and "no
    #### registered callback at all" meaning "anything goes".  Kept so staged enforcement can
    #### tell a redirect_uri that was *already* being rejected from one that only the stricter
    #### check rejects -- the first has to keep being rejected, and only the second gets the grace
    #### period.
    ##########################################################################

    test 'the legacy check matches on host only' do
      a = create_app(callback_url: 'https://app.example.com/cb')

      assert_equal true, a.redirect_uri_legacy_allowed?('https://app.example.com/anything-else'),
                   'which is the hole the stricter check closes'
      assert_equal true, a.redirect_uri_legacy_allowed?('http://app.example.com/cb'),
                   'and it did not care about the scheme either'
      assert_equal false, a.redirect_uri_legacy_allowed?('https://evil.example.com/cb')
    end

    # Reproducing the old check's blind spot is the point, not a bug: staging a check must not
    # change the answer for any request the old check accepted, and an application with no
    # registered callback is exactly such a request.  Falling back to #url here instead -- which
    # an earlier version did -- turns a staged log line into a hard rejection, which is how the
    # API Explorer broke.
    test 'the legacy check allows anything when no callback is registered' do
      a = create_app(callback_url: nil, url: 'https://app.example.com')

      assert_equal true, a.redirect_uri_legacy_allowed?('https://evil.example.com/cb')
      assert_equal true, a.redirect_uri_legacy_allowed?('https://app.example.com/cb')
    end

    test 'the legacy check treats a blank callback the same as a missing one' do
      assert_equal true, create_app(callback_url: '').redirect_uri_legacy_allowed?('https://evil.com/')
      assert_equal true, create_app(callback_url: '   ').redirect_uri_legacy_allowed?('https://evil.com/')
    end

    test 'the legacy check rejects an unparseable candidate' do
      a = create_app(callback_url: 'https://app.example.com/cb')

      assert_equal false, a.redirect_uri_legacy_allowed?(nil)
      assert_equal false, a.redirect_uri_legacy_allowed?('/cb')
    end

    # The relationship staged enforcement depends on: anything the strict check accepts, the
    # legacy check accepted too.  So turning the strict check on can only ever reject *more*,
    # never accept something that used to be refused.
    test 'the strict check is narrower than the legacy one, never wider' do
      a = create_app(callback_url: 'https://app.example.com/cb')

      [
        'https://app.example.com/cb',
        'https://app.example.com/cb?x=1',
        'https://app.example.com:443/cb',
        'https://app.example.com/cb/',
      ].each do |candidate|
        assert_equal true, a.redirect_uri_allowed?(candidate), candidate
        assert_equal true, a.redirect_uri_legacy_allowed?(candidate),
                     "#{candidate} is accepted by the strict check, so the legacy check must accept it too"
      end
    end

    ##########################################################################
    #### registered_origins
    ####
    #### The origins an application may receive an xd postMessage on.  callback_url and url carry
    #### an explicit scheme and are taken as they are; site_domain is a bare hostname, so a
    #### scheme has to be assumed -- and in production that assumption is https only, because
    #### granting http would hand the tokens to anyone who can answer for that host on a
    #### downgraded connection.
    ##########################################################################

    test 'origins are collected from the callback, the url and the site domain' do
      a = create_app(callback_url: 'https://cb.example.com/cb',
                     url: 'https://www.example.com/home',
                     site_domain: 'sd.example.com')

      assert_includes a.registered_origins, 'https://cb.example.com'
      assert_includes a.registered_origins, 'https://www.example.com'
      assert_includes a.registered_origins, 'https://sd.example.com'
    end

    test 'an origin is the scheme and host only, with no path' do
      a = create_app(callback_url: 'https://cb.example.com/deep/path?x=1', url: nil)

      assert_equal ['https://cb.example.com'], a.registered_origins
    end

    test 'a non-default port is part of the origin' do
      a = create_app(callback_url: 'https://cb.example.com:8443/cb', url: nil)

      assert_equal ['https://cb.example.com:8443'], a.registered_origins
    end

    test 'a default port is not part of the origin' do
      a = create_app(callback_url: 'https://cb.example.com:443/cb', url: nil)

      assert_equal ['https://cb.example.com'], a.registered_origins
    end

    # Dev and test registrations are routinely http, so both schemes are granted for a
    # site_domain there.  In production only https is, and that difference is the point of the
    # environment check.
    test 'a site domain grants http as well as https outside production' do
      a = create_app(callback_url: nil, url: nil, site_domain: 'sd.example.com')

      assert_equal ['test', true], [Platform::Config.env.to_s, a.registered_origins.include?('http://sd.example.com')]
      assert_includes a.registered_origins, 'https://sd.example.com'
    end

    test 'a site domain grants https only in production' do
      a = create_app(callback_url: nil, url: nil, site_domain: 'sd.example.com')

      Platform::Config.stubs(:env).returns('production')

      assert_equal ['https://sd.example.com'], a.registered_origins
    end

    test 'a site domain written with a scheme or a path is reduced to its host' do
      assert_includes create_app(callback_url: nil, url: nil, site_domain: 'https://sd.example.com').
                        registered_origins, 'https://sd.example.com'
      assert_includes create_app(callback_url: nil, url: nil, site_domain: 'http://sd.example.com/x').
                        registered_origins, 'https://sd.example.com'
    end

    test 'origins are de-duplicated' do
      a = create_app(callback_url: 'https://www.example.com/cb', url: 'https://www.example.com/home')

      assert_equal ['https://www.example.com'], a.registered_origins
    end

    test 'blank registrations contribute nothing' do
      a = create_app(callback_url: nil, url: '', site_domain: '   ')

      assert_equal [], a.registered_origins
    end

    ##########################################################################
    #### origin_allowed? and default_origin
    ##########################################################################

    test 'a registered origin is allowed' do
      a = create_app(callback_url: 'https://cb.example.com/cb', url: nil)

      assert_equal true, a.origin_allowed?('https://cb.example.com')
    end

    test 'origin_allowed? compares the origin, so a path on it is still allowed' do
      a = create_app(callback_url: 'https://cb.example.com/cb', url: nil)

      assert_equal true, a.origin_allowed?('https://cb.example.com/some/page')
    end

    test 'an unregistered origin, a downgraded scheme and another port are not allowed' do
      a = create_app(callback_url: 'https://cb.example.com/cb', url: nil)

      assert_equal false, a.origin_allowed?('https://evil.example.com')
      assert_equal false, a.origin_allowed?('http://cb.example.com')
      assert_equal false, a.origin_allowed?('https://cb.example.com:8443')
    end

    # A browser extension's origin cannot be registered -- Chrome reports chrome-extension://<id>
    # and Firefox a per-installation moz-extension://<uuid>, while #registered_origins is built
    # from http(s) registrations.  That is why the xd_origin check has its own enforcement switch.
    test 'an extension origin is not allowed, which is why xd_origin is staged separately' do
      a = create_app(callback_url: 'https://cb.example.com/cb', url: nil)

      assert_equal false, a.origin_allowed?('chrome-extension://abcdefghijklmnop')
      assert_equal false, a.origin_allowed?('moz-extension://0d1b2c3d-4e5f-6071-8293-a4b5c6d7e8f9')
    end

    test 'an unparseable origin is not allowed' do
      a = create_app(callback_url: 'https://cb.example.com/cb', url: nil)

      assert_equal false, a.origin_allowed?(nil)
      assert_equal false, a.origin_allowed?('')
      assert_equal false, a.origin_allowed?('not a url')
    end

    test 'default_origin prefers the registered callback' do
      a = create_app(callback_url: 'https://cb.example.com/cb', url: 'https://www.example.com')

      assert_equal 'https://cb.example.com', a.default_origin,
                   'the callback is the page the flow was going to land on anyway'
    end

    test 'default_origin falls back to the application url' do
      a = create_app(callback_url: nil, url: 'https://www.example.com')

      assert_equal 'https://www.example.com', a.default_origin
    end

    test 'default_origin is nil when nothing is registered' do
      assert_nil create_app(callback_url: nil, url: nil).default_origin
    end

    ##########################################################################
    #### parse_uri and normalize_path
    ##########################################################################

    test 'parse_uri requires a scheme and a host' do
      assert_not_nil Platform::Application.parse_uri('https://app.example.com/cb')
      assert_nil Platform::Application.parse_uri('app.example.com/cb')
      assert_nil Platform::Application.parse_uri('/cb')
    end

    # "https://" parses with a scheme and an *empty* host rather than a nil one, so the nil check
    # does not catch it and a URI comes back.  Harmless where it is used -- the empty host cannot
    # equal a registered host, so #redirect_uri_allowed? still says no -- but worth pinning,
    # because a caller that reads parse_uri as "nil unless this is a usable absolute URL" would be
    # wrong.  Platform::Helper.origin_of tests the same thing with #blank? and does reject it.
    test 'parse_uri accepts a scheme with an empty host' do
      assert_not_nil Platform::Application.parse_uri('https://')
      assert_equal '', Platform::Application.parse_uri('https://').host

      a = create_app(callback_url: 'https://app.example.com/cb')
      assert_equal false, a.redirect_uri_allowed?('https://'), 'it is still not an allowed target'
      assert_nil Platform::Helper.origin_of('https://')
    end

    test 'parse_uri rejects a URL carrying userinfo' do
      assert_nil Platform::Application.parse_uri('https://registered.example.com@evil.com'),
                 'it parses with host evil.com, which is the trick this closes'
    end

    test 'parse_uri returns nil rather than raising on junk' do
      assert_nil Platform::Application.parse_uri(nil)
      assert_nil Platform::Application.parse_uri('')
      assert_nil Platform::Application.parse_uri('::::')
      assert_nil Platform::Application.parse_uri('http://[')
    end

    test 'normalize_path treats an empty path and a bare slash alike' do
      assert_equal '/', Platform::Application.normalize_path('')
      assert_equal '/', Platform::Application.normalize_path('/')
      assert_equal '/', Platform::Application.normalize_path(nil)
    end

    test 'normalize_path drops one trailing slash and adds a leading one' do
      assert_equal '/cb',     Platform::Application.normalize_path('/cb')
      assert_equal '/cb',     Platform::Application.normalize_path('/cb/')
      assert_equal '/cb',     Platform::Application.normalize_path('cb')
      assert_equal '/a/b',    Platform::Application.normalize_path('/a/b/')
    end

  end # class ApplicationRedirectTest
end # module Platform
