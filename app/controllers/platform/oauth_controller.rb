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

module Platform
  class OauthController < BaseController

    # Client authentication, PKCE, xd origin handling and the session parameter allowlist.
    # Kept in lib so the same code runs on every Rails branch this gem supports.
    include Platform::OauthHardening

    if defined?(SslRequirement)
      include SslRequirement
      ssl_required :authorize, :request_token, :invalidate_token, :validate_token, :auth_success,
                   :revoke
    end

    skip_before_action :validate_guest_user

    layout Platform::Config.oauth_layout

    # http://tools.ietf.org/html/draft-ietf-oauth-v2-16#section-4.1
    # supports response_type = code, token
    def authorize
      if request_param(:client_id).blank?
        return redirect_with_response(:error_description => "client_id must be provided", :error => :invalid_request)
      end

      unless client_application
        return redirect_with_response(:error_description => "invalid client application id", :error => :unauthorized_application)
      end

      log_authorize_request

      save_oauth_login_redirect_params

      if Platform::Config.current_user_is_guest?
        return redirect_to Platform::Config.login_url(:client_id => request_param(:client_id), :display => display)
      end

      if redirect_url_required? and redirect_url.blank?
        return redirect_with_response(:error_description => "redirect_uri must be provided as a parameter or in the application callback_url property", :error => :invalid_request)
      end

      unless ["code","token"].include?(response_type)
        return redirect_with_response(:error_description => "only code and token response types are currently supported", :error => :unsupported_response_type)
      end

      unless redirect_url_valid?(redirect_url)
        @error = "redirect_uri cannot point to a different server than the one configured in the application"
        return render_action("authorize_failure", :status => 403)
      end

      send("oauth2_authorize_#{response_type}")
    end

    def xd?
      ['popup', 'hidden'].include?(display)
    end

    def auth_success
      render :layout => false
    end

    def auth_failed
      render :layout => false
    end

    # http://tools.ietf.org/html/draft-ietf-oauth-v2-16#section-4.2
    # supported grant_type = authorization_code, password, refresh_token, client_credentials
    def request_token
      # presented_client_id, not request_param(:client_id): RFC 6749 section 2.3.1 lets a client
      # send client_id and client_secret as HTTP Basic credentials instead of as parameters, and a
      # client that does so has still provided a client_id.
      if presented_client_id.blank?
        return render_response(:error_description => "client_id must be provided", :error => :invalid_request)
      end

      unless client_application
        return render_response(:error_description => "invalid client application id", :error => :unauthorized_application)
      end

      unless ["authorization_code", "password", "refresh_token", "client_credentials"].include?(grant_type)
        return render_response(:error_description => "only authorization_code, password and refresh_token grant types are currently supported", :error => :unsupported_grant_type)
      end

      # Not rejected, because this is how the flow is documented -- oauth_server_side shows the
      # whole exchange, client_secret included, as a GET query string.  But a credential in a URL
      # is a credential in access logs, Referer headers and browser history, so log who is still
      # doing it: RFC 6749 section 3.2 requires the token endpoint to accept POST.
      unless request.post?
        Platform::Logger.info(
          "OAUTH_TOKEN_REQUEST_NOT_POST app=#{client_application.try(:id)} grant=#{grant_type} " \
          "method=#{request.method.to_s.upcase} - credentials are travelling in the URL"
        )
      end

      send("oauth2_request_token_#{grant_type}")
    end
    alias :token :request_token

    # Both of these took a bare token and no credentials, which made validate_token a free
    # token-validity oracle for anyone who wanted to test a captured string, and invalidate_token
    # a way for anyone holding a token to kill it.  RFC 7009 section 2.1 requires the client to
    # authenticate, and both are now scoped to the authenticated client's own tokens -- one
    # application has no business reading or revoking another's.
    def validate_token
      return if revocation_request_rejected?

      token = presented_token_for_client
      if token && token.valid_token?
        render_response(:result => "OK")
      else
        render_response(:error => :invalid_token, :error_description => "invalid token")
      end
    end

    # add jsonp support
    def invalidate_token
      return if revocation_request_rejected?

      token = presented_token_for_client
      token.invalidate! if token

      # "OK" whether or not a token was found, per RFC 7009 section 2.2: telling the caller that
      # the token it named did not exist is the oracle we just closed.
      render_response(:result => "OK")
    end

    # RFC 7009 names this endpoint "revoke", and /oauth/revoke has been routed to a #revoke that
    # never existed.
    alias :revoke :invalidate_token

    def deauthorize
      unless Platform::Config.current_user_is_guest?
        client_application.deauthorize_user if client_application
      end
      render_response(:result => "OK")
    end

    def logout
      if Platform::Config.site_user_info_enabled?
        begin
          # send, not eval.  The string is configuration rather than request input, so this was
          # not reachable from outside, but eval will run whatever that string happens to contain
          # and the only thing ever configured here is a bare method name ("logout!").
          send(Platform::Config.logout_method)
        rescue Exception => ex
          raise "Failed to execute #{Platform::Config.logout_method} with exception: #{ex.message}"
        end
      else
        # handle default logout strategy
      end

      render_response(:result => "OK")
    end

    def xd
      render :layout => false
    end

    # XD only method - for now
    def status
      if params[:origin].blank?
        return redirect_with_response(:status => "unknown", :error => :invalid_request, :error_description => "origin must be specified")
      end

      unless client_application
        return redirect_with_response(:status => "unknown", :error => :invalid_request, :error_description => "client_id must be specified")
      end

      # Compared only the host against site_domain, so an http origin passed a check meant to
      # establish that the caller is the registered application.  #origin_allowed? compares the
      # whole origin, and against every callback the developer registered rather than site_domain
      # alone.
      unless client_application.origin_allowed?(params[:origin])
        return redirect_with_response(:status => "unknown", :error => :invalid_request, :error_description => "Unauthorized access - invalid origin.")
      end

      if Platform::Config.current_user_is_guest?
        return redirect_with_response(:status => "unknown")
      end

      # implement authorized user
      if client_application.authorized_user?
        return redirect_with_response(:status => "authorized")
      end

      redirect_with_response(:status => "unauthorized")
    end

  private

    # Stash just enough of the request to resume the authorize flow after the user logs in.
    #
    # This used to store the whole params hash.  The login controller and the social-login path
    # later hand that hash straight to redirect_to, so every key an authorize URL happened to
    # carry became part of a routing hash -- including :host, :protocol, :controller and
    # :only_path, which is how a routing hash becomes an off-site redirect.  See
    # Platform::OauthHardening::OAUTH_LOGIN_PARAM_KEYS.
    def save_oauth_login_redirect_params
      session[:oauth_login_redirect_params] = oauth_login_redirect_params
    end

    def remove_oauth_login_redirect_params
      session[:oauth_login_redirect_params] = nil
    end

    def request_param(key)
      params[key].to_s.strip.blank? ? nil : params[key].to_s.strip
    end

    # The client_id may arrive as a parameter or, for the token and revocation endpoints, in an
    # HTTP Basic header -- RFC 6749 section 2.3.1 makes Basic the preferred way to present
    # client_id and client_secret together, and a client that does so should not also have to
    # repeat the id in the query string.
    def presented_client_id
      @presented_client_id ||= request_param(:client_id) || http_basic_client_credentials.first
    end

    def client_application
      return nil if presented_client_id.blank?
      @client_application ||= Platform::Application.for(presented_client_id)
    end

    ##########################################################################
    #### Revocation / introspection
    ##########################################################################

    # Returns true when it has already rendered a rejection and the action should stop.
    #
    # Every requirement here is new -- these two endpoints took a bare token and nothing else --
    # so all of it is staged behind :revocation_auth.  With the switch off a caller that sends no
    # credentials still gets the old behaviour, including the unscoped token lookup in
    # #presented_token_for_client, and the log says what would have happened.
    def revocation_request_rejected?
      if presented_client_id.blank?
        return true if reject_revocation!('no client_id presented')
        return false  # legacy: no client to authenticate, no scoping
      end

      unless client_application
        render_response(:error_description => "invalid client application id", :error => :unauthorized_application)
        return true
      end

      # GET on a revocation endpoint puts the token in the URL, where it lands in access logs and
      # Referer headers -- and makes revocation reachable by any page that can cause a navigation.
      unless request.post?
        return true if reject_revocation!("#{action_name} over #{request.method.to_s.upcase}")
      end

      if (failure = authenticate_client!(action_name, :revocation_auth))
        render_response(failure)
        return true
      end

      false
    end

    # Log-or-reject for the revocation endpoints.  Returns true once it has rendered.
    def reject_revocation!(reason)
      return false unless oauth_violation!(:revocation_auth, reason)

      render_response(:error_description => "#{action_name} requires an authenticated client over POST",
                      :error => :invalid_client)
      true
    end

    # The token named by the request.
    #
    # Scoped to the authenticated client's own application -- one application has no business
    # reading or revoking another's tokens.  When no client identified itself and the switch is
    # off, there is nothing to scope to and this falls back to the unscoped lookup the endpoint
    # has always done.
    def presented_token_for_client
      presented = request_param(:access_token) || request_param(:token)
      return nil if presented.blank?

      token = Platform::Oauth::OauthToken.find_by_presented_token(presented)
      return nil if token.nil?

      return token if client_application.nil?
      return nil unless token.application_id == client_application.id

      token
    end

    def redirect_url
      @redirect_url ||= request_param(:redirect_url) || request_param(:redirect_uri) || client_application.try(:callback_url)
    end

    def redirect_url_required?
      return false if xd? or desktop?
      true
    end

    # web_server, user_agent
    def type
      @type ||= request_param(:type) || "web_server"
    end

    # What the request asked for.
    def scope
      @scope ||= request_param(:scope) || "basic"
    end

    # What we are actually willing to grant.
    #
    # The requested scope used to be stored on the token and echoed back untouched, so a client
    # received whatever it asked for.  Narrowing needs something to narrow against, and
    # #permission_keywords is empty while Platform::Config.enable_permissions? is off -- so with
    # no registration on file this logs that it could not check and passes the request through,
    # which is the existing behaviour.  See Platform::Application#granted_scope.
    def authorized_scope
      @authorized_scope ||= begin
        requested = scope

        granted =
          if client_application.scope_registration_known?
            client_application.granted_scope(requested)
          elsif oauth_violation!(:scope, "cannot narrow scope=#{requested.inspect} - application has no registered permissions")
            # Enforcing, with nothing on file to check the request against: grant the minimum
            # rather than the request.
            'basic'
          else
            requested
          end

        if granted != requested
          Platform::Logger.info(
            "OAUTH_SCOPE_NARROWED app=#{client_application.try(:id)} " \
            "requested=#{requested.inspect} granted=#{granted.inspect}"
          )
        end

        granted
      end
    end

    def grant_type
      @grant_type ||= request_param(:grant_type) || "authorization_code"
    end

    def response_type
      @response_type ||= request_param(:response_type) || "code"
    end

    def display
      @display ||= begin
        if mobile_device?
          "mobile"
        elsif params[:display]
          CGI.escapeHTML(params[:display])
        else
          "web"
        end
      end
    end

    def jsonp?
      not params[:callback].blank?
    end

    def desktop?
      display == "desktop"
    end

    def iframe?
      display == "iframe"
    end

    def mobile?
      display == "mobile"
    end

    # needs to be configured through Platform::Config
    def authenticate_user(username, password)
      Platform::Config.user_class.authenticate(username, password)
    end

    # request token with grant_type = authorization_code
    def oauth2_request_token_authorization_code
      if request_param(:code).blank?
        return render_response(:error_description => "Code must be provided", :error => :invalid_request)
      end

      # This grant did not authenticate the client at all: it matched the code against the
      # application_id and nothing else, so anyone who got hold of a code -- from a Referer
      # header, a proxy log, an open redirect on the client's host -- could redeem it, using only
      # the public client_id.  The documented server-side flow has always sent client_secret
      # (developer/help/oauth_server_side), so requiring it here is enforcing the published
      # contract rather than adding a requirement.
      if (failure = authenticate_client!('authorization_code'))
        return render_response(failure)
      end

      # The code itself is stored as a digest, so look it up through the token model rather than
      # by matching the presented value against the column.
      request_token = Platform::Oauth::RequestToken.find_by_presented_token(request_param(:code))

      # One message for "no such code", "expired", "already invalidated" and "belongs to another
      # application".  The original SQL filtered expiry and invalidation out of the lookup, so all
      # of these already answered the same way, and that is the right answer: RFC 6749 section 5.2
      # has a single invalid_grant for a code that is invalid, expired or revoked, because telling
      # the caller which one it is tells it whether the code ever existed.
      if request_token.nil? ||
         request_token.application_id != client_application.id ||
         !request_token.valid_token?
        return render_response(:error_description => "Invalid authorization code", :error => :invalid_request)
      end

      if request_token.callback_url != redirect_url
        return render_response(:error_description => "Redirection url must match the url used for the code request", :error => :invalid_request)
      end

      if (failure = verify_pkce!(request_token))
        return render_response(failure)
      end

      access_token  = client_application.find_or_create_access_token(request_token.user, request_token.scope)
      refresh_token = client_application.create_refresh_token(access_token.user, access_token.scope)
      request_token.destroy

      render_response(:access_token  => access_token.client_token,
                      :refresh_token => refresh_token.client_token,
                      :scope         => access_token.scope,
                      :expires_in    => (access_token.valid_to.to_i - Time.now.to_i))
    end

    # request token with grant_type = password
    def oauth2_request_token_password
      unless client_application.allow_grant_type_password?
        return render_response(:error_description => "This application is not authorized to use grant_type password", :error => :unauthorized_application)
      end

      if request_param(:username).blank?
        return render_response(:error_description => "Username must be provided", :error => :invalid_request)
      end

      if request_param(:password).nil?
        return render_response(:error_description => "Password must be provided", :error => :invalid_request)
      end

      # An unauthenticated password grant is a credential-testing oracle: anyone who knows the
      # public client_id of an application holding this permission could post username/password
      # pairs here, against this endpoint's rate limits rather than the login form's lockout, MFA
      # and captcha.  A client using this grant is confidential by definition -- it is handling
      # the user's actual password -- so there is no public-client case to accommodate.
      #
      # The grant itself is removed in OAuth 2.1 (RFC 9700 section 2.4) and should be retired;
      # this only stops it from being open to the world in the meantime.
      #
      # Staged on its own switch rather than the one the other grants use:
      # developer/help/oauth_trusted_client documents this grant with client_id, username and
      # password and never mentions client_secret, so clients following that page have never sent
      # one and enforcing it here will break them.  The authorization_code and refresh_token
      # grants are the opposite case -- their documentation has always shown the secret -- and
      # should not have to wait behind this.
      if (failure = authenticate_client!('password', :client_secret_password))
        return render_response(failure)
      end

      user = authenticate_user(request_param(:username), request_param(:password))
      unless user
        return render_response(:error_description => "Invalid username and/or password combination", :error => :invalid_request)
      end

      granted       = client_application.granted_scope(scope)
      access_token  = client_application.find_or_create_access_token(user, granted)
      refresh_token = client_application.create_refresh_token(access_token.user, access_token.scope)
      render_response(:access_token  => access_token.client_token,
                      :refresh_token => refresh_token.client_token,
                      :scope         => access_token.scope,
                      :expires_in    => (access_token.valid_to.to_i - Time.now.to_i))
    end

    # request token with grant_type = client_credentials
    def oauth2_request_token_client_credentials
      unless client_application.allow_grant_type_client_credentials?
        return render_response(:error_description => "This application is not authorized to use grant_type client_credentials", :error => :unauthorized_application)
      end

      if presented_client_secret.nil?
        return render_response(:error_description => "Application secret must be provided", :error => :invalid_request)
      end

      # secure_compare rather than !=: a byte-by-byte string comparison returns faster the earlier
      # it finds a difference, which leaks the length of the matching prefix.  This is the one
      # place the secret was already being checked, so it is the one place that leak was
      # reachable.
      #
      # No oauth_violation! staging here: this grant has always required the secret, so enforcing
      # it cannot break a client that was working.
      unless Platform::Helper.secure_compare(presented_client_secret, client_application.secret)
        return render_response(:error_description => "Invalid application secret", :error => :invalid_request)
      end

      granted       = client_application.granted_scope(scope)
      client_token  = client_application.create_client_token(granted)
      refresh_token = client_application.create_refresh_token(nil, granted)
      render_response(:access_token  => client_token.client_token,
                      :refresh_token => refresh_token.client_token,
                      :scope         => client_token.scope,
                      :expires_in    => (client_token.valid_to.to_i - Time.now.to_i))
    end

    # request token with grant_type = refresh_token
    def oauth2_request_token_refresh_token
      if request_param(:refresh_token).blank?
        return render_response(:error_description => "Refresh token must be provided", :error => :invalid_request)
      end

      # Same gap as the authorization_code grant: the refresh token was matched on
      # application_id and nothing else, so a leaked refresh token was redeemable by anyone with
      # the public client_id.  Also documented as sending client_secret.
      if (failure = authenticate_client!('refresh_token'))
        return render_response(failure)
      end

      refresh_token = Platform::Oauth::RefreshToken.find_by_presented_token(request_param(:refresh_token))

      if refresh_token.nil? || refresh_token.application_id != client_application.id
        return render_response(:error_description => "Invalid refresh token", :error => :invalid_request)
      end

      # Refresh tokens rotate, so a token that was already redeemed and is being presented again
      # has two holders and we cannot tell which is the real client: the whole family goes.  Note
      # #replayed? rather than #invalidated? -- an ordinary revocation is not a replay.  See
      # RefreshToken#replay!.
      if refresh_token.replayed?
        refresh_token.replay!
        return render_response(:error_description => "Refresh token has already been used - all tokens for this application have been revoked, please re-authorize",
                               :error => :invalid_grant)
      end

      unless refresh_token.valid_token?
        return render_response(:error_description => "Refresh token expired", :error => :invalid_request)
      end

      if refresh_token.user
        access_token = client_application.create_access_token(refresh_token.user, refresh_token.scope)
      else
        access_token = client_application.create_client_token(refresh_token.scope)
      end
      refresh_token.exchanged!

      refresh_token = client_application.create_refresh_token(access_token.user, access_token.scope)
      render_response(:access_token  => access_token.client_token,
                      :refresh_token => refresh_token.client_token,
                      :scope         => access_token.scope,
                      :expires_in    => (access_token.valid_to.to_i - Time.now.to_i))
    end

    # authorize with response_type = code
    def oauth2_authorize_code
      if request.post? or client_application.trusted?
        remove_oauth_login_redirect_params

        if params[:authorize] == '1' or client_application.trusted?
          Platform::ApplicationUser.touch(client_application)
          code = client_application.create_request_token(Platform::Config.current_user, redirect_url,
                                                         authorized_scope,
                                                         Platform::Config.oauth_request_token_lifetime,
                                                         requested_pkce_challenge)
          return redirect_with_response(:code       => code.code,
                                        :scope      => code.scope,
                                        :expires_in => (code.valid_to.to_i - Time.now.to_i))
        end

        if iframe? and client_application.auto_signin?
          return redirect_to(Platform::Config.default_url)
        end

        return redirect_with_response(:status => :unauthorized, :message => "canceled")
      end

      render_action("authorize")
    end

    # authorize with response_type = token
    def oauth2_authorize_token
      if request.post? or client_application.trusted?
        remove_oauth_login_redirect_params

        if params[:authorize] == '1' or client_application.trusted?
          Platform::ApplicationUser.touch(client_application)
          access_token = client_application.find_or_create_access_token(Platform::Config.current_user, authorized_scope)
          response_params = {:access_token => access_token.client_token,
                             :scope        => access_token.scope,
                             :expires_in   => (access_token.valid_to.to_i - Time.now.to_i)}

          if xd?
            # The "token" response type implements OAuth2's implicit grant, which should not return refresh_tokens
            # because the implicit grant usually depends on browser redirects to return the credentials to the client
            # application.  This creates vulnerabilities in redirect URL validation, leakage via the subsequent
            # HTTP_REFERER header, and leakage in the browser history.  Our XD (cross-domain) implementation avoids
            # all of those problems by using postMessage to transfer the tokens back to the Geni JSDK or whatever
            # client code requested the popup or hidden display.  There is still the issue of how to securely store
            # the refresh token but it could be used as part of a session cookie without much risk.  So for XD requests
            # we will return a refresh_token that can be used to avoid repeated calls to the authorize endpoint.

            response_params[:refresh_token] = client_application.create_refresh_token(access_token.user, access_token.scope).client_token
          end

          return redirect_with_response(response_params)
        end

        if iframe? and client_application.auto_signin?
          return redirect_to(Platform::Config.default_url)
        end

        return redirect_with_response(:status => :unauthorized, :message => "canceled")
      end

      render_action("authorize")
    end

    # Does this redirect_uri match something the developer registered?
    #
    # This used to return true for anything URI.parse would accept, which is to say for anything
    # -- the only redirect_uri it ever rejected was one that would not parse.  RFC 6749 section
    # 3.1.2 requires the authorization server to compare the redirect_uri against a registered
    # value, because the redirect is where the code or token is delivered.
    #
    # xd and desktop are genuinely exempt: neither redirects anywhere.  The xd flow postMessages
    # to a registered origin (see #xd_target_origin) and desktop redirects to this server's own
    # auth_success action, so for both of them redirect_url is never a destination.
    #
    # Staging must not loosen anything.  The old check already rejected a redirect_uri whose host
    # did not match the registered callback, so that rejection stands whether or not the switch is
    # on; only what the *stricter* check adds -- the scheme, the port, the path, and the case of
    # an application with nothing registered -- waits for the switch.
    def redirect_url_valid?(url)
      return true if xd? or desktop?
      return false if url.blank?
      return false if client_application.nil?

      # Our own API Explorer lander, which cannot match a third-party app's callback by
      # construction.  See #explorer_lander_redirect? for why this is safe.
      return true if explorer_lander_redirect?(url)

      return true if client_application.redirect_uri_allowed?(url)

      # Rejected by the check that was already in force: keep rejecting it.
      return false unless client_application.redirect_uri_legacy_allowed?(url)

      # Same host, but a different scheme, port or path -- or no registered callback to compare
      # against.  Newly rejected, so it waits for the switch.
      not oauth_violation!(:redirect_uri,
                           "redirect_uri=#{url.inspect} matches no registered callback " \
                           "(registered: #{client_application.registered_redirect_uris.inspect})")
    end

    # used by the authorization process
    def redirect_with_response(response_params, opts = {})
      response_params = HashWithIndifferentAccess.new(response_params)

      # preserve state
      response_params[:state] = request_param(:state) if request_param(:state)

      # The requested scope is no longer echoed back over the granted one.  It used to be, which
      # meant the scope in the response was whatever the client asked for rather than what it got
      # -- so a client could not tell when its request had been narrowed, and the response looked
      # like confirmation of the request.  Callers that grant a scope now put it in
      # response_params themselves; only fill it in if nobody did.
      #
      # Guarded on client_application: this method also renders the "client_id must be provided"
      # and "invalid client application id" errors, and #authorized_scope asks the application
      # what it is registered for.
      if response_params[:scope].blank? && request_param(:scope) && client_application
        response_params[:scope] = authorized_scope
      end

      # process xd popup
      if xd?
        target_origin = xd_target_origin

        if target_origin.blank?
          if xd_payload_carries_credentials?(response_params)
            # Only reachable with :xd_origin enforced -- while it is staged, #xd_target_origin
            # always returns something (the claimed origin, or "*").  So this is the enforcing
            # case with nothing registered to post to and a credential to post: refusing costs a
            # broken popup for an unregistered application, where delivering to "*" would hand
            # the credential to whatever opened the window.
            Platform::Logger.error(
              "OAUTH_XD_NO_TARGET_ORIGIN app=#{client_application.try(:id) || '-'} " \
              "- refusing to postMessage a credential; register a callback_url, url or site_domain"
            )
            @error = "This application has no registered origin to return the response to"
            # Named explicitly rather than through render_action: that interpolates #display, and
            # there is no authorize_failure_hidden template for display=hidden.  The popup
            # template is the right shape for both xd displays.
            return render(:action => "authorize_failure_popup", :layout => false, :status => 400)
          end

          # No credential in the payload, so there is nothing here to leak.  #status answers
          # callers it cannot identify at all (no client_id, hence no registered origin), and
          # those answers still have to reach them.
          target_origin = '*'
        end

        # Deliberately a different ivar from the one #xd_target_origin memoizes on: this one is
        # what the template posts to, and it may have been widened to "*" above for a payload
        # with nothing in it to protect.
        @xd_post_target   = target_origin
        @xd_payload_query = xd_payload_query(response_params)
        return render(:action => :xd, :layout => false)
      end

      response_query = begin
        prms = []
        response_params.keys.map(&:to_s).sort.each do |key|
          prms << "#{key}=#{CGI.escape(response_params[key.to_sym].to_s)}"
        end
        prms.join("&")
      end

      # for desktop apps - redirect to local urls
      if desktop?
        if response_params[:error_description] or response_params[:status] == 'unauthorized'
          return redirect_to(:action => :auth_failed, :anchor => response_query)
        else
          return redirect_to(:action => :auth_success, :anchor => response_query)
        end
      end

      if redirect_url_required? and redirect_url.blank?
        @error = response_params[:error_description]
        return render_action("authorize_failure")
      end

      redirect_uri = URI.parse(redirect_url)
      redirect_uri.path = (redirect_uri.path.blank? ? "/" : redirect_uri.path) unless mobile? # mobile apps will not have path
      redirect_uri.query = redirect_uri.query.blank? ? response_query : redirect_uri.query + "&#{response_query}"
      redirect_to(redirect_uri.to_s, :allow_other_host => true)
    end

    # used by the request token process
    def render_response(response_params, opts = {})
      response_params = HashWithIndifferentAccess.new(response_params)

      # preserve state
      response_params[:state] = request_param(:state) if request_param(:state)

      # The requested scope is no longer echoed over the granted one -- see the same change in
      # #redirect_with_response.  Grant paths set :scope from the token they issued.

      # we need to support json and redirect based method as well
      if jsonp?
        render(:text => "#{params[:callback].strip}(#{response_params.to_json})")
      else
        opts[:status] ||= begin
          if [:unsupported_grant_type, :invalid_request, :invalid_token, :invalid_grant,
              :unsupported_response_type].include?(response_params[:error])
            400
          elsif [:unauthorized_application, :invalid_client].include?(response_params[:error])
            # RFC 6749 section 5.2: invalid_client is a 401, and a client that authenticated with
            # an Authorization header is told which scheme to retry with.
            response.headers['WWW-Authenticate'] = 'Basic realm="oauth"' if response_params[:error] == :invalid_client
            401
          else
            200
          end
        end
        render(:json => response_params.to_json, :status => opts[:status])
      end
    end

    def render_action(action, opts={})
      if display == 'web'
        render(opts.merge(:action => "#{action}_#{display}"))
      else
        render(opts.merge(:action => "#{action}_#{display}", :layout => false))
      end
    end

  end # class OauthController
end # module Platform
