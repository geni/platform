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
  class BaseController < ApplicationController

    before_action :init_platform
    before_action :validate_platform_enabled
    before_action :validate_guest_user

    if Platform::Config.before_actions.any?
      before_action *Platform::Config.before_actions
    end

    if Platform::Config.skip_before_actions.any?
      skip_before_action *Platform::Config.skip_before_actions
    end

    if Platform::Config.after_actions.any?
      after_action *Platform::Config.after_actions
    end

    layout Platform::Config.site_layout

    helper BaseHelper

    if Platform::Config.helpers.any?
      helper *Platform::Config.helpers
    end

    def platform_current_user
      Platform::Config.current_user
    end
    helper_method :platform_current_user

    def platform_current_developer
      Platform::Config.current_developer
    end
    helper_method :platform_current_developer

    def platform_current_user_is_admin?
      Platform::Config.current_user_is_admin?
    end
    helper_method :platform_current_user_is_admin?

    def platform_current_user_is_guest?
      Platform::Config.current_user_is_guest?
    end
    helper_method :platform_current_user_is_guest?

    def platform_current_user_is_developer?
      Platform::Config.current_user_is_developer?
    end
    helper_method :platform_current_user_is_developer?

    def mobile_device?
      return false if request.user_agent.blank?
      ua = request.user_agent.downcase
      ['iphone', 'android'].any? {|agent| ua.index(agent)}
    end
    helper_method :mobile_device?

  private

    def init_platform
      site_current_user = nil
      begin
        site_current_user = eval(Platform::Config.current_user_method)
        site_current_user = nil unless site_current_user.is_a?(Platform::Config.user_class)
      rescue StandardError => ex
        raise "Platform cannot be initialized because #{Platform::Config.current_user_method} failed with: #{ex.message}"
      end

      # initialize request thread variables
      Platform::Config.init(site_current_user)
    end

    # Back to wherever the request came from.
    #
    # params[:source_url] is request input, so this was an open redirect: anything that could get
    # a viewer to follow a link to one of the actions using it -- the forum and rating deletes,
    # the admin edit screens -- could choose where that viewer ended up.  Rails 7 started raising
    # ActionController::Redirecting::UnsafeRedirectError on an off-host redirect_to rather than
    # following it, which turned the hole into a 500 but did not fix it.
    #
    # Both candidates are now checked against this host and dropped if they fail, which is what
    # "the source" was ever meant to be: a page on this site that the viewer was just on.
    def redirect_to_source(default_url = nil)
      source = [params[:source_url], request.env['HTTP_REFERER']].find { |url| this_host?(url) }

      return redirect_to(source) if source
      return redirect_to(default_url) if default_url
      redirect_to_site_default_url
    end

    # A path with no host of its own, or an absolute url pointing back at this host.
    def this_host?(url)
      return false if url.blank?

      uri = URI.parse(url)
      return true if uri.host.nil?

      uri.host == request.host && uri.port == request.port
    rescue URI::InvalidURIError
      false
    end

    def redirect_to_site_default_url
      redirect_to(Platform::Config.default_url)
    end

    def page
      return 1 unless params[:page].present?
      params[:page].to_i
    end

    def per_page
      return 30 unless params[:per_page].present?
      params[:per_page].to_i
    end

    # handle disabled state for Platform
    def validate_platform_enabled
      if Platform::Config.disabled?
        trfe("You don't have rights to access that section.")
        return redirect_to_site_default_url
      end
    end

    # guest users can still switch between languages outside of the site
    def validate_guest_user
      if platform_current_user_is_guest?
        trfe("You must be a registered user in order to access this section of the site.")
        return redirect_to_site_default_url
      end
    end

  end # class BaseController
end # module Platform