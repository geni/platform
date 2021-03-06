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
  class Config

    def self.init(site_current_user, current_application = nil)
      Thread.current[:platform_current_user] = site_current_user
      Thread.current[:platform_current_developer] = Platform::Developer.for(site_current_user)
      Thread.current[:platform_current_application] = current_application
    end

    def self.current_user
      Thread.current[:platform_current_user]
    end

    def self.current_developer
      Thread.current[:platform_current_developer] 
    end

    def self.current_application
      Thread.current[:platform_current_application]
    end

    def self.current_application=(app)
      Thread.current[:platform_current_application] = app
    end

    def self.current_user_is_developer?
      Thread.current[:platform_current_developer] != nil
    end

    def self.reset!
      Thread.current[:platform_current_user] = nil
      Thread.current[:platform_current_developer] = nil
      Thread.current[:platform_current_application] = nil
    end

    def self.models
      @models ||= begin 
        mdls = [
            Platform::ApplicationDeveloper, Platform::ApplicationPermission, Platform::ApplicationUser,
            Platform::ApplicationCategory, Platform::Category, 
            Platform::ForumMessage, Platform::ForumTopic,
            Platform::Permission, Platform::Rating,
            Platform::Developer, Platform::Application, 
            Platform::Oauth::OauthToken, Platform::Oauth::AccessToken, 
            Platform::Oauth::RequestToken, Platform::Oauth::RefreshToken,
            Platform::Media::Media, Platform::Media::Image,
            Platform::ApplicationLog, Platform::RollupLog, 
            Platform::ApplicationMetric, Platform::DailyApplicationMetric, 
            Platform::WeeklyApplicationMetric, Platform::MonthlyApplicationMetric, 
            Platform::TotalApplicationMetric, Platform::ApplicationUsageMetric,
            Platform::LoggedException,
            Platform::DeveloperActivity, Platform::DeveloperRole, Platform::Role
        ]
      
        if user_class_name == "Platform::PlatformUser" # used for stand-alone deployment only
          mdls << [Platform::PlatformUser, Platform::PlatformAdmin] 
        end  
      
        mdls.flatten
      end
    end
  
    def self.reset_all!
      models.each do |cls|
        puts ">> Resetting #{cls.name}..."
        cls.delete_all
      end

      init_default_categories

      puts "Done."
    end
  
    def self.system_user
      return nil unless site_info[:system_user_id]
      @system_user ||= user_class_name.constantize.find_by_id(site_info[:system_user_id])
    end

    def self.system_developer
      @system_developer ||= Platform::Developer.find_or_create(Platform::Config.system_user)
    end

    def self.init_default_applications
      puts "Initializing default applications..."
      unless system_developer
        puts "Cannot initialize default application because system user id is not specified in the config."
        return
      end
  
      default_applications.each do |keyword, description|
        app = Platform::Application.create(description.merge(:developer => system_developer))
        puts "Initialized #{app.name}."
      end    
    end

    def self.init_default_categories
      puts "Initializing default categories..."
      init_categories(Platform::Category.root, default_categories)
    end

    def self.init_categories(parent, categories) 
      categories.each do |keyword, info|
        cat = Platform::Category.create(:parent => parent, :keyword => keyword, :name => info[:name], :position => info[:position])
        init_categories(cat, info[:categories]) if info[:categories]
      end
    end

    def self.default_applications
      @default_applications ||= load_yml("/config/platform/data/default_applications.yml")
    end

    def self.default_categories
      @default_categories ||= load_yml("/config/platform/data/default_categories.yml")
    end

    def self.root
      Rails.root
    end
  
    def self.env
      Rails.env
    end

    def self.load_yml(file_path, for_env = env)
      yml_path = "#{root}#{file_path}"
      yml = YAML.load_file(yml_path)
      yml = yml['defaults'].rmerge(yml[for_env] || {}) unless for_env.nil?
      HashWithIndifferentAccess.new(yml)
    end

    def self.config
      @config ||= load_yml("/config/platform/config.yml")
    end

    def self.enabled?
      config[:enable_platform] 
    end

    def self.disabled?
      not enabled?
    end

    def self.enable_app_directory?
      config[:enable_app_directory]
    end

    def self.enable_embedded_applications?
      config[:enable_embedded_applications]
    end

    def self.enable_mobile_applications?
      config[:enable_mobile_applications]
    end

    def self.enable_developer_agreement?
      config[:enable_developer_agreement]
    end

    def self.developer_agreement_path
      config[:developer_agreement_path]
    end

    def self.enable_app_statistics?
      config[:enable_app_statistics]
    end

    def self.enable_api_verification?
      config[:enable_api_verification]
    end

    def self.default_app_icon
      "/assets/platform/default_app_icon.gif"
    end
  
    def self.default_app_logo
      "/assets/platform/default_app_logo.gif"
    end  
  
    #########################################################
    # Config Sections
    #########################################################
    def self.caching
      config[:caching]
    end

    def self.logger
      config[:logger]
    end
  
    def self.site_info
      config[:site_info]
    end

    def self.api
      config[:API]
    end
    #########################################################

    #########################################################
    # Caching
    #########################################################
    def self.enable_caching?
      caching[:enabled]
    end

    def self.cache_adapter
      caching[:adapter]
    end

    def self.cache_store
      caching[:store]
    end

    def self.cache_version
      caching[:version]
    end
    #########################################################

    #########################################################
    # Logger
    #########################################################
    def self.enable_logger?
      logger[:enabled]
    end

    def self.log_path
      logger[:log_path]
    end
    #########################################################

    #########################################################
    # Site Info
    def self.site_title
      site_info[:title] 
    end

    def self.site_logo_url
      site_info[:logo_url] 
    end
  
    def self.site_base_url
      site_info[:base_url]
    end  
  
    def self.default_url
      site_info[:default_url]
    end

    def self.site_layout
      site_info[:platform_layout]
    end

    def self.admin_layout
      site_info[:admin_layout]
    end

    def self.oauth_web_layout
      site_info[:oauth_web_layout]
    end

    def self.oauth_fluid_layout
      site_info[:oauth_fluid_layout]
    end

    def self.oauth_popup_layout
      site_info[:oauth_popup_layout]
    end

    def self.oauth_mobile_layout
      site_info[:oauth_mobile_layout]
    end

    def self.oauth_desktop_layout
      site_info[:oauth_desktop_layout]
    end

    def self.media_directory
      site_info[:media_directory]
    end

    def self.media_path
      "#{root}/public#{media_directory}"
    end

    def self.helpers
      return [] unless site_info[:helpers]
      @tr8n_helpers ||= site_info[:helpers].collect{|helper| helper.to_sym}
    end

    def self.admin_helpers
      return [] unless site_info[:admin_helpers]
      @admin_helpers ||= site_info[:admin_helpers].collect{|helper| helper.to_sym}
    end
  
    def self.skip_before_filters
      return [] unless site_info[:skip_before_filters]
      @skip_before_filters ||= site_info[:skip_before_filters].collect{|filter| filter.to_sym}
    end

    def self.before_filters
      return [] unless site_info[:before_filters]
      @before_filters ||= site_info[:before_filters].collect{|filter| filter.to_sym}
    end

    def self.after_filters
      return [] unless site_info[:after_filters]
      @after_filters ||= site_info[:after_filters].collect{|filter| filter.to_sym}
    end

    #########################################################
    # site user info
    # The following methods could be overloaded in the initializer
    #########################################################
    def self.site_user_info
      site_info[:user_info]
    end

    def self.current_user_method
      site_user_info[:current_user_method]
    end

    def self.logout_method
      site_user_info[:logout_method]
    end

    def self.login_url(params = {})
      site_info[:login_url] + (site_info[:logout_url].index('?') ? ':' : '?') + params.collect{|n,v| "#{n}=#{CGI.escape(v.to_s)}"}.join('&') 
    end

    def self.logout_url(params = {})
      site_info[:logout_url] + (site_info[:logout_url].index('?') ? ':' : '?') + params.collect{|n,v| "#{n}=#{CGI.escape(v.to_s)}"}.join('&') 
    end

    def self.site_user_info_enabled?
      site_user_info[:enabled].nil? ? true : site_user_info[:enabled]
    end

    def self.site_user_info_disabled?
      !site_user_info_enabled?
    end
  
    def self.user_class_name
      return site_user_info[:class_name] if site_user_info_enabled?
      "Platform::PlatformUser"  
    end

    def self.user_class
      user_class_name.constantize
    end

    def self.user_id(user = current_user)
      user.send(site_user_info[:methods][:id])
    rescue Exception => ex
      Platform::Logger.error("Failed to fetch user id: #{ex.to_s}")
      0
    end

    def self.user_name(user = current_user)
      user.send(site_user_info[:methods][:name])
    rescue Exception => ex
      Platform::Logger.error("Failed to fetch #{user_class_name} name: #{ex.to_s}")
      "Unknown user"
    end

    def self.user_email(user = current_user)
      user.send(site_user_info[:methods][:email])
    rescue Exception => ex
      Platform::Logger.error("Failed to fetch #{user_class_name} name: #{ex.to_s}")
      nil
    end

    def self.user_gender(user = current_user)
      user.send(site_user_info[:methods][:gender])
    rescue Exception => ex
      Platform::Logger.error("Failed to fetch #{user_class_name} name: #{ex.to_s}")
      "unknown"
    end

    def self.user_mugshot(user = current_user)
      mugshot_image = user.send(site_user_info[:methods][:mugshot])
      return silhouette_image(user) if mugshot_image.blank?
      mugshot_image
    rescue Exception => ex
      Platform::Logger.error("Failed to fetch #{user_class_name} image: #{ex.to_s}")
      silhouette_image
    end

    def self.user_link(user = current_user)
      user.send(site_user_info[:methods][:link])
    rescue Exception => ex
      Platform::Logger.error("Failed to fetch #{user_class_name} link: #{ex.to_s}")
      "/tr8n"
    end

    def self.user_locale(user = current_user)
      user.send(site_user_info[:methods][:locale])
    rescue Exception => ex
      Platform::Logger.error("Failed to fetch #{user_class_name} locale: #{ex.to_s}")
      default_locale
    end

    def self.admin_user?(user = current_user)
      user.send(site_user_info[:methods][:admin])
    rescue Exception => ex
      Platform::Logger.error("Failed to fetch #{user_class_name} admin flag: #{ex.to_s}")
      false
    end

    def self.current_user_is_admin?
      admin_user?
    end
  
    def self.guest_user?(user = current_user)
      return true unless user
      user.send(site_user_info[:methods][:guest])
    rescue Exception => ex
      Platform::Logger.error("Failed to fetch #{user_class_name} guest flag: #{ex.to_s}")
      true
    end
  
    def self.current_user_is_guest?
      guest_user?
    end
    #########################################################

    #########################################################
    # site media info
    # The following methods could be overloaded in the initializer
    #########################################################
    def self.site_media_info
      site_info[:media_info]
    end

    def self.site_media_enabled?
      site_media_info[:enabled]
    end

    def self.site_media_class
      return "Platform::Media::Image" unless site_media_enabled?
      site_media_info[:class_name]
    end

    def self.site_media_write_method
      site_media_info[:write_method]
    end
  
    def self.create_media(file)
      media = site_media_class.constantize.create
      media.send(site_media_write_method, file)
      media
    rescue Exception => ex
      pp ex
      Platform::Logger.error("Failed to create media: #{ex.to_s}")
      nil
    end

    def self.logo_url(media)
      eval("media.#{site_media_info[:logo_url_method]}")
    rescue Exception => ex
      Platform::Logger.error("Failed to fetch logo url: #{ex.to_s}")
      default_app_logo
    end

    def self.icon_url(media)
      eval("media.#{site_media_info[:icon_url_method]}")
    rescue Exception => ex
      Platform::Logger.error("Failed to fetch icon url: #{ex.to_s}")
      default_app_icon
    end
    #########################################################

    #########################################################
    # Application Directory
    #########################################################
    def self.featured_apps_enabled?
      true
    end

    def self.featured_apps_title
      "Featured Applications"
    end

    def self.featured_apps_per_row
      2
    end

    def self.featured_apps_per_page
      2
    end

    def self.suggested_apps_title
      "Applications You May Like"
    end

    def self.suggested_apps_per_row
      5
    end

    def self.suggested_apps_per_page
      20
    end

    def self.searched_apps_title
      "Search Results"
    end

    def self.searched_apps_per_page
      15
    end
  
    #########################################################
    # API
    #########################################################
    def self.enable_api?
      api[:enabled]
    end

    def self.api_config_path
      api[:config_path]
    end
    
    def self.api_logging_enabled?
      api[:logging_enabled]
    end
  
    def self.api_request_limit
      api[:request_limit]
    end
  
    def self.api_cookies_enabled?
      api[:cookies_enabled]
    end

    def self.api_allow_public?
      api[:allow_public]
    end

    def self.api_max_models
      api[:max_models]
    end

    def self.api_request_window
      api[:request_window]
    end

    def self.api_token_lifetime
      api[:token_lifetime]
    end

    def self.api_request_limit
      api[:request_limit]
    end
  
    def self.api_base_url
      api[:base_url]
    end  

    def self.api_scheme
      api[:scheme]
    end  

    def self.api_supported_versions
      api[:supported_versions]
    end  

    def self.api_supported_version_options
      @api_supported_version_options ||= api[:supported_versions].collect{|v| ["v #{v}", v]}
    end  
  
    def self.api_default_version
      api[:default_version]
    end
  
    def self.api_explorer_app_id
      config[:api_explorer_app_id]
    end
  
    def self.api_explorer_app
      return if api_explorer_app_id.blank?
      @api_explorer_app ||= Platform::Application.find_by_id(api_explorer_app_id)
    end
      
    def self.api_explorer_app?
      !api_explorer_app_id.blank?
    end
    
    def self.api_proxies_path
      api[:proxies_path]
    end
    
    def self.load_proxies
      Dir["#{root}/#{api_proxies_path}/*_proxy_*.rb"].each do |file|
        require_or_load file
      end
    end  

    def self.proxies
      @proxies ||= {}
    end  
    
    #########################################################
    # API References
    #########################################################
  
    def self.api_reference(api_version = api_default_version)
      @api_reference ||= begin
        ref = HashWithIndifferentAccess.new
        api_supported_versions.each do |version|
          ref[version] = {}
          path = "#{root}/#{api[:config_path]}/#{version}"
          files = Dir.glob("#{path}/*.yml")
          files.each do |file|
            ref[version].merge!(YAML.load_file(file))
          end
        end  
        ref.freeze
      end
      @api_reference[api_version]
    end

    def self.api_reference_by_path(api_version,  path)
      @api_reference_by_path ||= {}
      @api_reference_by_path[api_version] ||= begin
        api = api_reference(api_version)
        by_path = {}
        api.each do |key, defs|
          by_path[defs["path"]] = api[key]
          (defs[:actions] || []).each do |act_key, acts|
            path = acts["path"] || "#{defs["path"]}/#{act_key}"
            by_path[path] = defs[:actions][act_key]
          end
        end
        by_path
      end
      @api_reference_by_path[api_version][path]
    end

    def self.api_explorer_groups(api_version = api_default_version)
      api[:explorer_groups][api_version]
    end
  
    #########################################################

    def self.silhouette_image(user = current_user)
      "/assets/platform/photo_silhouette.gif"
    end

    def self.features
      @features ||= begin
        defs = load_yml("/config/platform/site/features.yml")
        feats = []
        defs[:enabled_features].each do |key|
          defs[key][:key] = key
          feats << defs[key] 
        end
        feats
      end
    end

  end
end
