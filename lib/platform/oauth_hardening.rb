#--
# Copyright (c) 2011 Michael Berkovich
#
# Permission is hereby granted, free of charge, to any person obtaining
# a copy of this software and associated documentation files (the
# "Software"), to deal in the Software without restriction, including
# without limitation the rights to use, copy, modify, merge, publish,
# distribute, sublicense, and/or sell copies of the Software, and to
# permit persons to whom the Software is furnished to do so, subject to
# the following conditions:
#
# The above copyright notice and this permission notice shall be
# included in all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
# EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
# MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
# NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE
# LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION
# OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION
# WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
#++

require 'base64'
require 'openssl'

# Client authentication, PKCE, cross-domain origin handling and the parameter allowlist for
# Platform::OauthController.
#
# This lives in its own module rather than in the controller so that the same code runs on every
# supported Rails branch: the controller file itself has diverged (namespacing, finder syntax,
# indentation) across rails-2.3.x through rails-8.0.x, and this has not.  Keep it free of
# version-specific API -- no `where`, no `find(:first)`, nothing that only one branch has.
module Platform
  module OauthHardening

    # Parameters worth carrying across a login redirect and back into the authorize request.
    #
    # The caller used to stash the whole params hash in the session, which meant an authorize URL
    # could inject anything it liked -- :host, :protocol, :controller, :only_path -- into the hash
    # that the login controller later hands to redirect_to.  Only these keys mean anything to
    # #authorize, so only these are kept.
    #
    # :controller and :action are deliberately absent: the hash still needs them to route, but
    # taking them from params is how you let an authorize URL pick which controller the user
    # lands on after logging in.  #oauth_login_redirect_params fills them in from the request
    # that is actually executing.
    OAUTH_LOGIN_PARAM_KEYS = %w[
      client_id redirect_uri redirect_url response_type
      state scope display origin callback type code_challenge code_challenge_method
    ].freeze

    # Keys the cross-domain response may carry back to the opener.  Everything else the request
    # happened to contain stays out of the message -- see #xd_response_payload.
    XD_RESPONSE_KEYS = %w[
      access_token refresh_token expires_in scope state status message
      error error_description code callback
    ].freeze

    PKCE_METHODS = %w[S256].freeze

    # The API Explorer's OAuth lander: a fixed path on this server.
    EXPLORER_LANDER_PATH = '/platform/developer/api_explorer/oauth_lander'.freeze

    # The keys whose presence makes an xd payload worth protecting.  A response carrying one of
    # these must go to a verified origin or not be sent at all; a response that carries none --
    # an error, or a "status: unknown" for a caller we could not even identify -- has nothing in
    # it to steal, and refusing to deliver those would break the JSDK's status check for every
    # unregistered caller.
    XD_CREDENTIAL_KEYS = %w[access_token refresh_token code].freeze

  private

    ##########################################################################
    #### Staged enforcement
    ##########################################################################

    # Should the caller reject this request?
    #
    # True once the check is switched on in Platform::Config.  While it is off this logs what it
    # would have rejected and returns false, so a check can be deployed, watched, and then turned
    # on -- the point being that several of these reject requests that third-party clients have
    # been getting away with for years, and the logs are the only way to find out which clients
    # those are before breaking them.
    #
    # Log lines are deliberately uniform and greppable:
    #   OAUTH_WOULD_REJECT check=client_secret app=42 path=/oauth/token reason=...
    def oauth_violation!(check, reason)
      return true if Platform::Config.oauth_enforce?(check)

      Platform::Logger.error(
        "OAUTH_WOULD_REJECT check=#{check} app=#{client_application.try(:id) || '-'} " \
        "path=#{request.path} reason=#{reason}"
      )
      false
    end

    ##########################################################################
    #### Client authentication (RFC 6749 section 2.3)
    ##########################################################################

    # [client_id, client_secret] from an HTTP Basic header, which RFC 6749 section 2.3.1 makes the
    # preferred way to present them.  The components are form-urlencoded before being base64'd,
    # per that section.
    def http_basic_client_credentials
      return @http_basic_client_credentials if defined?(@http_basic_client_credentials)

      @http_basic_client_credentials = begin
        header = basic_authorization_header

        # /m, and the whitespace is squeezed out of the captured value before decoding, because
        # Base64.encode64 wraps at 60 characters -- which ActionController's own
        # HttpAuthentication::Basic.encode_credentials uses, and "client_id:client_secret" is 81
        # bytes here, so the header legitimately arrives with a newline in the middle of it.
        if header =~ /\ABasic\s+(.+)\z/im
          id, secret = Base64.decode64($1.gsub(/\s+/, '')).split(':', 2)
          [unescape_credential(id), unescape_credential(secret)]
        else
          [nil, nil]
        end
      end
    end

    # request.headers first, falling back to the raw env key.  The gem reads the header both ways
    # in different places (Platform::Api::BaseController uses request.headers["Authorization"]),
    # and on Rails 2.3 request.headers is a thin wrapper that does not always normalise the way
    # later versions do.
    def basic_authorization_header
      header = request.headers['Authorization'] if request.respond_to?(:headers)
      header = request.env['HTTP_AUTHORIZATION'] if header.nil? || header.to_s.empty?
      header.to_s
    end

    def unescape_credential(value)
      return nil if value.nil?
      CGI.unescape(value)
    rescue StandardError
      value
    end

    def presented_client_secret
      @presented_client_secret ||= begin
        secret = request_param(:client_secret)
        secret = http_basic_client_credentials.last if secret.nil?
        secret.to_s.empty? ? nil : secret
      end
    end

    # Does the request prove it is the client it claims to be?
    #
    # secure_compare rather than ==: the secret is a comparison against a stored credential, and
    # the host app already does this for its own tokens (Rack::Utils.secure_compare in
    # login_controller).
    def client_authenticated?
      return false if client_application.nil?
      return false if presented_client_secret.nil?

      Platform::Helper.secure_compare(presented_client_secret, client_application.secret)
    end

    # Enforce client authentication for a grant that requires it.  Returns nil when the request
    # may proceed, or a response hash for the caller to render.
    #
    # A public client -- a desktop, mobile or in-browser app that cannot keep a secret -- is
    # exempt, because shipping a secret inside a distributed binary does not authenticate
    # anything (RFC 6749 section 2.1).  What such a client has to bring instead is PKCE, which
    # #verify_pkce! requires of it.
    def authenticate_client!(grant_type, check = :client_secret)
      return nil if client_authenticated?

      if client_application.try(:public_client?)
        Platform::Logger.info(
          "OAUTH_PUBLIC_CLIENT app=#{client_application.id} grant=#{grant_type} " \
          "- skipping client_secret, PKCE required instead"
        )
        return nil
      end

      reason = presented_client_secret.nil? ? 'no client_secret presented' : 'client_secret did not match'
      return nil unless oauth_violation!(check, "grant=#{grant_type} #{reason}")

      # "invalid_client", not "invalid_request": the request was well formed, the client just did
      # not authenticate.  RFC 6749 section 5.2.
      { :error => :invalid_client,
        :error_description => "Client authentication failed - client_secret must be provided and must match" }
    end

    ##########################################################################
    #### Instrumentation
    ##########################################################################

    # One line per authorize request, so the enforcement rollout is a lookup rather than
    # archaeology.
    #
    # Nothing else records this.  click_logs keeps the request URI, so response_type can be dug
    # out of it with a regex, but it does not record the HTTP method -- and
    # platform_application_logs, which does, has not been written since 2022.  Between them they
    # cannot answer "which applications use the implicit grant", "which send PKCE" or "which
    # would be affected if we required POST", which are the three questions the rollout turns on.
    # See agent-docs/OAUTH_ENFORCEMENT_ROLLOUT.md in the host application.
    #
    # Called before the response_type and redirect_uri checks run, deliberately: a request those
    # reject still has to appear here, because the rejections are the thing being counted.
    #
    # Logs the *origin* of the redirect_uri rather than the whole value.  The path and query can
    # carry identifiers, and OAUTH_WOULD_REJECT already records the full value on the requests
    # that fail.
    def log_authorize_request
      challenge = request_param(:code_challenge)
      pkce = if challenge.nil?
               'none'
             else
               method = (request_param(:code_challenge_method) || 'S256').upcase
               PKCE_METHODS.include?(method) ? method : "unsupported:#{log_safe(method)}"
             end

      sent_redirect = !(request_param(:redirect_url) || request_param(:redirect_uri)).nil?
      redirect_shown = if sent_redirect
                         log_safe(Platform::Helper.origin_of(redirect_url) || 'unparseable', 80)
                       else
                         'omitted'
                       end

      Platform::Logger.info(
        "OAUTH_AUTHORIZE app=#{client_application.id} " \
        "method=#{request.method.to_s.upcase} " \
        "response_type=#{log_value(request_param(:response_type), 'code(default)')} " \
        "display=#{log_safe(display)} " \
        "pkce=#{pkce} " \
        "scope=#{log_value(request_param(:scope), 'basic(default)', 120)} " \
        "redirect_uri=#{redirect_shown} " \
        "state=#{request_param(:state).nil? ? 'omitted' : 'sent'} " \
        "trusted=#{client_application.trusted? ? 'yes' : 'no'} " \
        "public_client=#{client_application.public_client? ? 'yes' : 'no'}"
      )
    rescue StandardError => ex
      # Instrumentation must not be able to fail an authorization.
      Platform::Logger.error("OAUTH_AUTHORIZE logging failed: #{ex.class}: #{ex.message}") rescue nil
    end

    # response_type, display, scope and code_challenge_method all come straight from the request.
    # A newline in any of them would let a caller forge log lines, so they are reduced to
    # characters that cannot restructure the output and truncated.
    # Sanitise only what the caller supplied.  Our own "(default)" markers are not request data
    # and must survive intact -- running them through log_safe turned code(default) into
    # code_default_, which is exactly the distinction this field exists to record.
    def log_value(raw, default, limit = 40)
      raw.nil? ? default : log_safe(raw, limit)
    end

    def log_safe(value, limit = 40)
      value.to_s.gsub(/[^A-Za-z0-9_.:\/@\-]/, '_')[0, limit]
    end

    ##########################################################################
    #### First-party redirect targets
    ##########################################################################

    # Is this redirect_uri our own API Explorer lander?
    #
    # The Explorer is a first-party tool: a developer signs in through it to get a token to try
    # API calls with.  It redirects to a fixed path on *this* server
    # (api_explorer.js#getAccessToken), which by definition can never match the developer's own
    # registered callback -- and it has been getting away with that by sending display=mobile,
    # which used to switch redirect_uri validation off entirely.  Removing that bypass is what
    # broke it.
    #
    # Allowing this one destination is not a hole.  The token lands on a page we serve, which
    # hands it to window.opener through a same-origin JS call; a page on another origin that
    # opened the popup can neither read that window's URL nor be called into across origins, so
    # naming this URL as a redirect_uri gets an attacker nothing.
    #
    # The host is checked against Platform::Config.site_base_url and *not* against request.host.
    # request.host comes from the Host header, which a caller can set -- trusting it would turn
    # this allowance into "redirect my token anywhere, as long as the path matches".
    #
    # http as well as https because the Explorer's JS prepends a scheme when its configured base
    # URL carries none, and the QA hosts are reached over http.
    def explorer_lander_redirect?(url)
      uri = Platform::Application.parse_uri(url)
      return false if uri.nil?
      return false unless %w[http https].include?(uri.scheme)
      return false unless Platform::Application.normalize_path(uri.path) == EXPLORER_LANDER_PATH

      return true if own_oauth_host?(uri.host)

      # Path matched but the host did not.  Either someone is probing, or site_base_url does not
      # match the host the Explorer is actually served from -- and the second is miserable to
      # diagnose from a bare "cannot point to a different server", so say it out loud.
      Platform::Logger.error(
        "OAUTH_EXPLORER_LANDER_HOST_MISMATCH host=#{uri.host.inspect} " \
        "expected=#{Platform::Config.site_base_url.inspect} url=#{url.inspect}"
      )
      false
    end

    def own_oauth_host?(host)
      host = host.to_s.downcase
      return false if host.empty?

      configured = Platform::Config.site_base_url.to_s.downcase
                     .sub(%r{\Ahttps?://}, '').sub(%r{[/:].*\z}, '')
      return false if configured.empty?

      host == configured
    end

    ##########################################################################
    #### PKCE (RFC 7636)
    ##########################################################################

    # The challenge an authorize request wants bound to the code it is about to be issued.
    # Returns nil when the request sent none, which is every request today -- PKCE is additive
    # and no existing client sends it.
    #
    # Only S256 is accepted.  RFC 7636 also defines "plain", but it offers no protection against
    # an attacker who can read the authorization request, and since nothing is using PKCE here
    # yet there is no legacy client to accommodate.
    def requested_pkce_challenge
      challenge = request_param(:code_challenge)
      return nil if challenge.nil?

      method = (request_param(:code_challenge_method) || 'S256').upcase
      return nil unless PKCE_METHODS.include?(method)

      { :code_challenge => challenge, :code_challenge_method => method }
    end

    # Verify a code_verifier against the challenge stored on the authorization code.  Returns nil
    # when the request may proceed, or a response hash for the caller to render.
    def verify_pkce!(request_token)
      challenge = request_token.code_challenge

      if challenge.to_s.empty?
        # The code was issued without a challenge, so there is nothing to verify against.  A
        # public client should have sent one; that is what the pkce check is for.
        return nil unless client_application.try(:public_client?)
        return nil unless oauth_violation!(:pkce, 'public client exchanged a code issued without a code_challenge')

        return { :error => :invalid_request,
                 :error_description => "code_challenge is required for this application" }
      end

      verifier = request_param(:code_verifier)
      if verifier.nil?
        return nil unless oauth_violation!(:pkce, 'code issued with a code_challenge was exchanged without a code_verifier')

        return { :error => :invalid_grant, :error_description => "code_verifier must be provided" }
      end

      unless Platform::Helper.secure_compare(pkce_transform(verifier, request_token.code_challenge_method), challenge)
        # Always rejected, switch or no switch.  Unlike the other checks this cannot break a
        # client that was working: the only way to get here is to present a verifier that does
        # not match a challenge the same client chose moments earlier.
        return { :error => :invalid_grant, :error_description => "code_verifier did not match code_challenge" }
      end

      nil
    end

    def pkce_transform(verifier, method)
      case method.to_s.upcase
      when 'S256', ''
        Base64.urlsafe_encode64(OpenSSL::Digest::SHA256.digest(verifier.to_s)).delete('=')
      else
        # Unknown method stored on the code: produce something that cannot match.
        nil
      end
    end

    ##########################################################################
    #### Cross-domain (xd) responses
    ##########################################################################

    # The exact origin to postMessage the response to.
    #
    # The template used to post to "*", which hands the message to whatever opened the popup or
    # framed the hidden iframe.  Since redirect_url_valid? waves through any xd request, that was
    # enough for any page to open the authorize endpoint and collect a logged-in user's tokens.
    #
    # The JSDK already sends its own origin on every popup and hidden request
    # (Platform.Request._origin), and the consent form carries it through the POST, so there is a
    # claimed origin to check against what the developer registered.  There is deliberately no
    # switch on this one: the fallback for an unverifiable origin is a *narrower* target (the
    # app's registered origin) or no message at all, never "*".
    def xd_target_origin
      return @xd_target_origin if defined?(@xd_target_origin)

      @xd_target_origin = begin
        claimed = params[:origin]

        if claimed.present? && client_application.try(:origin_allowed?, claimed)
          Platform::Helper.origin_of(claimed)
        else
          registered = client_application.try(:default_origin)

          if claimed.present?
            Platform::Logger.error(
              "OAUTH_XD_ORIGIN_REJECTED app=#{client_application.try(:id) || '-'} " \
              "claimed=#{claimed.inspect} registered=#{client_application.try(:registered_origins).inspect} " \
              "- falling back to #{registered.inspect}"
            )
          end

          registered
        end
      end
    end

    # Only the response parameters go back to the opener.
    #
    # The template used to serialize the whole params hash, so anything the request carried came
    # back out -- including parameters an attacker put there, in a message the receiving page
    # trusts enough to dispatch on.
    def xd_response_payload(response_params)
      payload = {}

      XD_RESPONSE_KEYS.each do |key|
        value = response_params[key]
        # :callback is the JSDK's per-request correlation id and :state is the client's own CSRF
        # value; both come in on the request and have to come back out for the opener to match
        # the response to what it asked for.
        value = params[key] if value.nil? && %w[callback state].include?(key)
        next if value.nil? || value.to_s.empty?

        payload[key] = value.to_s
      end

      payload
    end

    # The payload as a query string.
    #
    # Hash#to_query, so values are escaped and keys are sorted.  A query string rather than JSON
    # because Platform.Request.onMessage only parses event.data when it is a string, and copies
    # of jsdk.js are hosted by third parties -- the wire format has to stay what it was.
    def xd_payload_query(response_params)
      xd_response_payload(response_params).to_query
    end

    def xd_payload_carries_credentials?(response_params)
      payload = xd_response_payload(response_params)
      XD_CREDENTIAL_KEYS.any? { |key| payload.key?(key) }
    end

    ##########################################################################
    #### Session hand-off across login
    ##########################################################################

    def oauth_login_redirect_params
      # From the executing request, not from params.  Keeps whichever controller the host app
      # actually routed /platform/oauth/authorize to -- Geni points it at its own subclass, and
      # hardcoding the gem's controller here would skip that subclass's overrides.
      allowed = { 'controller' => "/#{controller_path}", 'action' => action_name }

      OAUTH_LOGIN_PARAM_KEYS.each do |key|
        value = params[key]
        next if value.nil?
        next unless value.is_a?(String) || value.is_a?(Numeric) || value.is_a?(Symbol)

        allowed[key] = value.to_s
      end

      allowed
    end

  end
end
