class ApplicationController < ActionController::Base
  protect_from_forgery

  def current_user
    return nil unless session[:platform_user_id]
    @current_user ||= Platform::PlatformUser.find_by_id(session[:platform_user_id])
  end
  helper_method :current_user
end
