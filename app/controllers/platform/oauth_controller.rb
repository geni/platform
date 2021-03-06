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

# OAuth 2.0 Spec URL: http://tools.ietf.org/html/draft-ietf-oauth-v2-20
class Platform::OauthController < Platform::BaseController
  # ssl_required :authorize, :request_token, :invalidate_token, :validate_token, :revoke, :invalidate, :auth_success

  skip_before_filter :validate_guest_user  

  # http://tools.ietf.org/html/draft-ietf-oauth-v2-16#section-4.1
  # supports response_type = code, token 
  def authorize
    if request_param(:client_id).blank?
      return redirect_with_response(:error_description => "client_id must be provided", :error => :invalid_request)
    end

    unless client_application
      return redirect_with_response(:error_description => "invalid client application id", :error => :unauthorized_client)
    end

    platform_store_oauth_redirect_params
    
    if platform_current_user_is_guest?
      return redirect_to(platform_login_url)
    end

    if redirect_url_required? and redirect_url.blank?
      return redirect_with_response(:error_description => "redirect_uri must be provided as a parameter or in the application callback_url property", :error => :invalid_request)
    end
    
    unless ["code","token"].include?(response_type)
      return redirect_with_response(:error_description => "only code and token response types are currently supported", :error => :unsupported_response_type)
    end

    unless redirect_url_valid?(redirect_url)
      return redirect_with_response(:error_description => "redirect_uri cannot point to a different server than from the one it sent a request", :error => :invalid_request)
    end
    
    send("oauth2_authorize_#{response_type}")
  end

  # http://tools.ietf.org/html/draft-ietf-oauth-v2-16#section-4.2
  # supported grant_type = authorization_code, password, refresh_token, client_credentials
  def request_token
    if request_param(:client_id).blank?
      return render_response(:error_description => "client_id must be provided", :error => :invalid_request)
    end

    unless client_application
      return render_response(:error_description => "invalid client application id", :error => :unauthorized_client)
    end
    
    unless ["authorization_code", "password", "refresh_token", "client_credentials"].include?(grant_type)
      return render_response(:error_description => "only authorization_code, password and refresh_token grant types are currently supported", :error => :unsupported_grant_type)
    end

    send("oauth2_request_token_#{grant_type}")
  end 
  alias :token :request_token

  def auth_success
    render :layout => false  
  end

  def auth_failed
    render :layout => false  
  end

  def validate_token
    token = Platform::Oauth::OauthToken.find_by_token(request_param(:access_token))
    if token && token.authorized?
      render_response(:result => "OK")
    else
      render_response(:error => :invalid_token, :error_description => "invalid token")
    end
  end

  # add jsonp support
  def invalidate_token
    token = Platform::Oauth::OauthToken.find_by_token(request_param(:access_token))
    token.invalidate! if token
    render_response(:result => "OK")
  end
  
  def deauthorize
    unless Platform::Config.current_user_is_guest?
      client_application.deauthorize_user if client_application
    end
    render_response(:result => "OK")
  end

  def logout
    if Platform::Config.site_user_info_enabled?
      begin
        eval(Platform::Config.logout_method)
      rescue Exception => ex
        raise Platform::Exception.new("Failed to execute #{Platform::Config.logout_method} with exception: #{ex.message}")
      end
    else
      # handle default logout strategy
    end
    
    render_response(:result => "OK")
  end
  
  def xd?
    ['popup', 'hidden'].include?(display)
  end
  
  def xd
  	render :layout => false
  end

  # XD only method - for now
  def xd_status
    if params[:origin].blank?
      return redirect_with_response(:status => "unknown", :error => :invalid_request, :error_description => "origin must be specified")
    end
    
    unless client_application
      return redirect_with_response(:status => "unknown", :error => :invalid_request, :error_description => "client_id must be specified")
    end
    
    uri = URI.parse(params[:origin])
    unless uri.host == client_application.site_domain
      return redirect_with_response(:status => "unknown", :error => :invalid_request, :error_description => "Anauthorized access - invalid origin.")
    end
    
    if Platform::Config.current_user_is_guest?
      return redirect_with_response(:status => "unknown")
    end

    # implement authorized user
    if client_application.authorized_user?
      # add access token to the redirect
      access_token = client_application.create_access_token(:user=>Platform.current_user, :scope=>scope)
      refresh_token = client_application.create_refresh_token(:user=>Platform.current_user, :scope=>scope)
      return redirect_with_response(:status => "authorized", :access_token => access_token.token, :refresh_token => refresh_token.token, :expires_in => (access_token.valid_to.to_i - Time.now.to_i))
    end
    
    redirect_with_response(:status => "unauthorized")
  end 

private

  def request_param(key)
    params[key]
  end

  def client_application
    return nil if request_param(:client_id).blank?  
    @client_application ||= Platform::Application.for(request_param(:client_id))
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

  def scope
    @scope ||= request_param(:scope) || "basic"
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
        params[:display]
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
    User.authenticate(username, password)
  end

  # request token with grant_type = authorization_code
  def oauth2_request_token_authorization_code
    if request_param(:code).blank?
      return render_response(:error_description => "code must be provided", :error => :invalid_request)
    end
    
    request_token = Platform::Oauth::RequestToken.find(:first, :conditions => ["application_id = ? and token = ? and valid_to > ? and invalidated_at is null", 
                                                             client_application.id, request_param(:code), Time.now])
    unless request_token
      return render_response(:error_description => "invalid verification code", :error => :invalid_request)
    end
    
    if request_token.callback_url != redirect_url
      return render_response(:error_description => "redirection url must match the url used for the code request", :error => :invalid_request)
    end
    
    access_token = request_token.exchange!
    refresh_token = client_application.create_refresh_token(:user=>access_token.user, :scope=>scope)
    render_response(:access_token => access_token.token, :refresh_token => refresh_token.token, :expires_in => (access_token.valid_to.to_i - Time.now.to_i))
  end

  # request token with grant_type = password
  def oauth2_request_token_password
    unless client_application.allow_grant_type_password?
      return render_response(:error_description => "this application is not authorized to use grant_type password", :error => :unauthorized_application)
    end
    
    if request_param(:username).blank?
      return render_response(:error_description => "username must be provided", :error => :invalid_request)
    end
    
    if request_param(:password).nil?
      return render_response(:error_description => "password must be provided", :error => :invalid_request)
    end

    user = authenticate_user(request_param(:username), request_param(:password))
    unless user
      return render_response(:error_description => "invalid username and/or password", :error => :invalid_request)
    end
    
    access_token = client_application.create_access_token(:user=>user, :scope=>scope)
    refresh_token = client_application.create_refresh_token(:user=>user, :scope=>scope)
    render_response(:access_token => access_token.token, :refresh_token => refresh_token.token, :expires_in => (access_token.valid_to.to_i - Time.now.to_i))
  end

  # request token with grant_type = client_credentials
  def oauth2_request_token_client_credentials
    unless client_application.allow_grant_type_client_credentials?
      return render_response(:error_description => "this application is not authorized to use grant_type client_credentials", :error => :unauthorized_application)
    end
    
    client_token = client_application.create_client_token(:scope=>scope)
    refresh_token = client_application.create_refresh_token(:scope=>scope)
    render_response(:access_token => client_token.token, :refresh_token => refresh_token.token, :expires_in => (client_token.valid_to.to_i - Time.now.to_i))
  end

  # request token with grant_type = refresh_token
  def oauth2_request_token_refresh_token
    if request_param(:refresh_token).blank?
      return render_response(:error_description => "refresh_token must be provided", :error => :invalid_request)
    end
    
    refresh_token = Platform::Oauth::RefreshToken.find(:first, :conditions => ["application_id = ? and token = ? and invalidated_at is null", client_application.id, request_param(:refresh_token)])
    unless refresh_token
      return render_response(:error_description => "invalid refresh token", :error => :invalid_request)
    end
    
    access_token = refresh_token.exchange!
    refresh_token = client_application.create_refresh_token(:user=>access_token.user, :scope=>scope)
    render_response(:access_token => access_token.token, :refresh_token => refresh_token.token, :expires_in => (access_token.valid_to.to_i - Time.now.to_i))
  end

  # authorize with response_type = code
  def oauth2_authorize_code
    if request.post?
      platform_remove_oauth_redirect_params

      if params[:authorize] == '1'
        Platform::ApplicationUser.touch(client_application)
        code = client_application.create_request_token(:user=>Platform::Config.current_user, :callback_url=>redirect_url, :scope => scope)
        return redirect_with_response(:code => code.code, :expires_in => (code.valid_to.to_i - Time.now.to_i))
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
    if request.post?
      platform_remove_oauth_redirect_params

      if params[:authorize] == '1'
        Platform::ApplicationUser.touch(client_application)
        access_token = client_application.create_access_token(:user=>Platform::Config.current_user, :scope=>scope)
        return redirect_with_response(:access_token => access_token.token, :expires_in => (access_token.valid_to.to_i - Time.now.to_i))
      end

      if iframe? and client_application.auto_signin?
        return redirect_to(Platform::Config.default_url)
      end

      return redirect_with_response(:status => :unauthorized, :message => "canceled")
    end   

    render_action("authorize")
  end

  def redirect_url_valid?(url)
    return true if xd? or mobile?
    
    begin
      URI.parse(url)
    rescue
      return false
    end

    true
  end
  
  # used by the authorization process
  def redirect_with_response(response_params, opts = {})
    response_params = HashWithIndifferentAccess.new(response_params)
    
    # preserve state
    response_params[:state] = request_param(:state) if request_param(:state)
    
    # more scope validation must be done
    response_params[:scope] = request_param(:scope) if request_param(:scope)
    
    # process xd popup
    if xd?
      params.merge!(response_params)
      return render(:action => :xd, :layout => false)
    end   

    response_query = response_params.collect{|n,v| "#{n}=#{CGI.escape(v.to_s)}"}.join("&")

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
    
    redirect_to(redirect_uri.to_s)
  end
  
  # used by the request token process
  def render_response(response_params, opts = {})
    response_params = HashWithIndifferentAccess.new(response_params)
    
    # preserve state
    response_params[:state] = request_param(:state) if request_param(:state)
    
    # more scope validation must be done
    response_params[:scope] = request_param(:scope) if request_param(:scope)

    # we need to support json and redirect based method as well
    if jsonp?
      render(:text => "#{params[:callback].strip}(#{response_params.to_json})")
    else  
      render(:json => response_params.to_json)
    end
  end
  
  def render_action(action)
    render(:action => "#{action}_#{display}", :layout => Platform::Config.site_info["oauth_#{display}_layout"])
  end    

end
