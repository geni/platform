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

# == Schema Information
#
# Table name: platform_applications
#
#  id                       :integer          not null, primary key
#  android_key_hash         :string
#  api_version              :string
#  auto_login               :boolean
#  auto_resize              :boolean
#  auto_signin              :boolean
#  callback_url             :string
#  canvas_name              :string
#  canvas_url               :string
#  consent_label            :text
#  contact_email            :string
#  deauthorize_callback_url :string
#  description              :text
#  key                      :string
#  locale                   :string
#  mobile_application_type  :string
#  name                     :string
#  permissions              :string
#  privacy_policy_url       :string
#  rank                     :integer
#  secret                   :string
#  site_domain              :string
#  state                    :string           default("new")
#  support_url              :string
#  terms_of_service_url     :string
#  url                      :string
#  version                  :string
#  created_at               :datetime
#  updated_at               :datetime
#  developer_id             :integer
#  icon_id                  :integer
#  ios_bundle_id            :string
#  itunes_app_store_id      :string
#  logo_id                  :integer
#  parent_id                :integer
#
# Indexes
#
#  index_platform_applications_on_developer_id  (developer_id)
#  index_platform_applications_on_key           (key) UNIQUE
#  index_platform_applications_on_parent_id     (parent_id)
#
module Platform
  class Application < ApplicationRecord

    # useful methods - should be public
    include Platform::SimpleStringPermissions

    acts_as_tree :order => 'version'

    belongs_to :developer, :class_name => 'Platform::Developer::Developer'
    has_many :application_developers, :dependent => :destroy
    has_many :application_metrics, :dependent => :destroy
    has_many :application_users, :dependent => :destroy
    has_many :application_logs, :dependent => :destroy

    has_many :tokens,           :class_name => 'Platform::Oauth::OauthToken', :dependent => :destroy
    has_many :access_tokens,    :class_name => 'Platform::Oauth::AccessToken', :dependent => :destroy
    has_many :refresh_tokens,   :class_name => 'Platform::Oauth::RefreshToken', :dependent => :destroy

    has_many :application_categories, :dependent => :destroy
    has_many :categories, :through => :application_categories

    has_many :application_permissions, :dependent => :destroy

    belongs_to :icon, :class_name => Platform::Config.site_media_class, :dependent => :destroy, :optional => true
    belongs_to :logo, :class_name => Platform::Config.site_media_class, :dependent => :destroy, :optional => true

    validates_presence_of :name, :key, :secret
    validates_uniqueness_of :key
    before_validation :generate_keys, :on => :create

    URL_REGEX = /\Ahttp(s?):\/\/(\w+:{0,1}\w*@)?(\S+)(:[0-9]+)?(\/|\/([\w#!:.?+=&%@!\-\/]))?/i
    validates_format_of :url,                   :with => URL_REGEX, :allow_blank=>true
    validates_format_of :support_url,           :with => URL_REGEX, :allow_blank=>true
    validates_format_of :privacy_policy_url,    :with => URL_REGEX, :allow_blank=>true
    validates_format_of :terms_of_service_url,  :with => URL_REGEX, :allow_blank=>true
    validates_format_of :canvas_url,            :with => URL_REGEX, :allow_blank=>true

    attr_accessor :token_callback_url

    acts_as_state_machine :initial => :new
    state :new
    state :submitted
    state :approved
    state :rejected
    state :blocked
    state :deprecated

    event :submit do
      transitions :from => :new,        :to => :submitted
      transitions :from => :rejected,   :to => :submitted
    end

    event :deprecate do
      transitions :from => :approved,   :to => :deprecated
    end

    event :block do
      transitions :from => :new,        :to => :blocked
      transitions :from => :submitted,  :to => :blocked
      transitions :from => :approved,   :to => :blocked
      transitions :from => :rejected,   :to => :blocked
    end

    event :unblock do
      transitions :from => :blocked,    :to => :new
    end

    event :approve do
      transitions :from => :new,        :to => :approved
      transitions :from => :submitted,  :to => :approved
    end

    event :reject do
      transitions :from => :submitted,  :to => :rejected
    end

    def self.for(client_id)
      app = Platform::Application.find_by_id(client_id) if client_id.match(/^[\d]+$/)
      app || Platform::Application.find_by_key(client_id)
    end

    def self.find_access_token(token_key)
      token   = Platform::Oauth::AccessToken.find_by_presented_token(token_key)
      token ||= Platform::Oauth::ClientToken.find_by_presented_token(token_key)

      if token && token.valid_token?
        token
      else
        nil
      end
    end

    def permission_keywords
      []
      # @permission_keywords ||= permissions.collect{|p| p.keyword.to_s}
    end

    def add_permission(key)
      key = key.to_s.strip
      return if permitted_to?(key)
      perm = Platform::Permission.for(key)
      return unless perm
      Platform::ApplicationPermission.create(:application => self, :permission => perm)
    end

    def permitted_to?(key)
      permission_keywords.include?(key.to_s)
    end

    # The scope to actually record on a token, given what the request asked for.
    #
    # The requested scope used to be stored verbatim and echoed back in the response, so the
    # value the client chose was the value it got -- there was never a step that narrowed it to
    # what the application is registered for.
    #
    # Narrowing only has teeth once applications carry registered permissions:
    # #permission_keywords returns [] while Platform::Config.enable_permissions? is off, and
    # intersecting with [] would reject everything.  So with nothing registered this returns the
    # request unchanged, which is the behaviour that has always been in place, and the caller logs
    # that it could not narrow.  Mapping scopes onto API resources is the part that still has to
    # be designed.
    def granted_scope(requested)
      requested = requested.to_s.strip
      return 'basic' if requested.empty?

      allowed = permission_keywords
      return requested if allowed.empty?

      (requested.split(',').map { |sc| sc.strip } & allowed).join(',')
    end

    # Can this application's scope request actually be checked against a registration?
    def scope_registration_known?
      not permission_keywords.empty?
    end

    def rate_limited(value=true)
      set_permission(:no_rate_limit, !value)
    end

    def rate_limited!(value=true)
      rate_limited(value)
      save!
    end

    def rate_limited?
      ! has_permission?(:no_rate_limit)
    end

    # Note the missing "!": #rate_limited above negates because the permission it writes is
    # itself a negation (:no_rate_limit), and that negation was copied here where the permission
    # is not.  The effect was that #trusted! marked an application *un*trusted and
    # #trusted!(false) marked it trusted, while #trusted? read the flag straight.  Worth fixing
    # even though nothing calls the writer today: #trusted? is what skips the consent screen.
    def trusted(value=true)
      set_permission(:trusted, value)
    end

    def trusted!(value=true)
      trusted(value)
      save!
    end

    def trusted?
      has_permission?(:trusted)
    end

    # A client that cannot keep a secret: a desktop, mobile or in-browser app whose "secret"
    # ships inside something the user can read.  Such a client is exempt from client_secret
    # authentication on the token endpoint, and is required to use PKCE instead.  RFC 6749
    # section 2.1.
    def public_client(value=true)
      set_permission(:public_client, value)
    end

    def public_client!(value=true)
      public_client(value)
      save!
    end

    def public_client?
      has_permission?(:public_client)
    end

    # Ticket 19135
    def allow_grant_type_password(value=true)
      set_permission(:grant_type_password, value)
    end

    # Ticket 19135
    def allow_grant_type_password!(value=true)
      allow_grant_type_password(value)
      save!
    end

    # Ticket 19135
    def allow_grant_type_password?
      has_permission?(:grant_type_password)
    end

    def allow_grant_type_client_credentials?
      true # for now, all applications have a right to get client_token
    end

    # Ticket 19180
    def allow_unlimited_models(value=true)
      set_permission(:unlimited_models, value)
    end

    # Ticket 19180
    def allow_unlimited_models!(value=true)
      allow_unlimited_models(value)
      save!
    end

    # Ticket 19180
    def allow_unlimited_models?
      has_permission?(:unlimited_models)
    end

    # Ticket 19507
    def allow_add_without_premium(value=true)
      set_permission(:add_without_premium, value)
    end

    # Ticket 19507
    def allow_add_without_premium!(value=true)
      allow_add_without_premium(value)
      save!
    end

    # Ticket 19507
    def allow_add_without_premium?
      has_permission?(:add_without_premium)
    end

    def tos_required(value=true)
      set_permission(:tos_required, value)
    end

    def tos_required!(value=true)
      tos_required(value)
      save!
    end

    def tos_required?
      has_permission?(:tos_required)
    end

    def default_terms_statement_tr_label
      links = []
      links << "[link_tos: Terms of Service]"   unless terms_of_service_url.blank?
      links << "[link_privacy: Privacy Policy]" unless privacy_policy_url.blank?

      return '' if links.empty?

      links = links.join(' and ')

      if tos_required?
        "I accept the {application} #{links}."
      else
        "By proceeding, you agree to the {application} #{links}."
      end
    end

    def terms_statement_tr_label
      result = self.consent_label
      result = default_terms_statement_tr_label if result.nil? or result.blank?
      result
    end

    ############################################################################
    #### Registered callbacks and origins
    ####
    #### Everything an authorize request is allowed to send the user back to, or postMessage a
    #### token to, is derived from what the developer registered on the application.  Nothing
    #### here consults the request.
    ############################################################################

    # The callbacks an authorize request may name in redirect_uri / redirect_url.
    #
    # #url is deliberately *not* in here even though the old host-only check fell back to it.  A
    # marketing homepage is not a redirect target, and treating it as one let an app with a blank
    # callback_url accept any redirect_uri on that host.
    def registered_redirect_uris
      [callback_url].reject { |u| u.nil? || u.to_s.strip.empty? }
    end

    # Does +candidate+ match a registered callback?
    #
    # Matches on scheme, host, port and path; the query string is free.  RFC 6749 section 3.1.2
    # asks for an exact string match, and the query string is the one piece of that we cannot
    # insist on: the FTDNA connector's callback carries a profile_id the host app rewrites per
    # request, and clients that append their own parameters are common.  Scheme, host, port and
    # path is what actually closes the holes -- a registered https callback can no longer be
    # downgraded to http, and no other path on the host is reachable.
    #
    # Comparing the parsed components rather than strings also means a candidate cannot smuggle a
    # different target past us through encoding tricks, userinfo
    # ("https://app.example.com@evil.com" parses with host evil.com) or a default port written
    # out in full.
    def redirect_uri_allowed?(candidate)
      candidate = Platform::Application.parse_uri(candidate)
      return false if candidate.nil?

      registered_redirect_uris.any? do |registered|
        registered = Platform::Application.parse_uri(registered)
        next false if registered.nil?

        candidate.scheme == registered.scheme &&
          candidate.host  == registered.host  &&
          candidate.port  == registered.port  &&
          Platform::Application.normalize_path(candidate.path) == Platform::Application.normalize_path(registered.path)
      end
    end

    # The check that was in force before #redirect_uri_allowed? existed: hosts only, with #url as
    # a fallback, and "no registered callback at all" meaning "anything goes".
    #
    # Kept so that staged enforcement can tell a redirect_uri that was *already* being rejected
    # from one that only the stricter check rejects.  The first has to keep being rejected --
    # staging a check must not loosen anything -- and only the second gets the grace period.  See
    # Platform::OauthController#redirect_url_valid?.
    # Mirrors the old check *exactly*, including its blind spot:
    #
    #   return true  if client_application.try(:callback_url).blank?
    #   Geni.app_callback_uri?(url, client_application)
    #
    # A blank callback_url short-circuited to true before #url was ever consulted, so the #url
    # fallback inside app_callback_uri? was unreachable for that case.  Reproducing that here
    # looks like a bug and is the point: staging a check must not change the answer for any
    # request the old check accepted, and an application with no registered callback is exactly
    # such a request.  Falling back to #url instead -- which an earlier version of this method
    # did -- turns a staged log into a hard rejection, which is how the API Explorer broke.
    def redirect_uri_legacy_allowed?(candidate)
      return true if callback_url.nil? || callback_url.to_s.strip.empty?

      candidate  = Platform::Application.parse_uri(candidate)
      registered = Platform::Application.parse_uri(callback_url)
      return false if candidate.nil? || registered.nil?

      candidate.host == registered.host
    end

    # The origins this application is allowed to receive an xd postMessage on.
    #
    # callback_url and url carry an explicit scheme and are taken as-is.  site_domain is stored
    # as a bare hostname, so a scheme has to be assumed, and in production that assumption is
    # https only: granting http would hand the tokens to anyone who can answer for that host on a
    # downgraded connection, which is the hole this check exists to close.  Dev and test
    # registrations are still routinely http, so they get both.
    def registered_origins
      origins = []

      [callback_url, url].each do |u|
        next if u.nil? || u.to_s.strip.empty?
        origin = Platform::Helper.origin_of(u)
        origins << origin if origin
      end

      unless site_domain.nil? || site_domain.to_s.strip.empty?
        host = site_domain.to_s.strip.sub(%r{\Ahttps?://}, '').sub(%r{/.*\z}, '')
        origins << "https://#{host}"
        origins << "http://#{host}" if %w[development test].include?(Platform::Config.env.to_s)
      end

      origins.uniq
    end

    def origin_allowed?(candidate)
      candidate = Platform::Helper.origin_of(candidate)
      return false if candidate.nil?

      registered_origins.include?(candidate)
    end

    # The origin to postMessage to when the request did not name a usable one.  Prefers the
    # registered callback, because that is the page the flow was going to land on anyway.
    def default_origin
      registered_origins.first
    end

    def self.parse_uri(url)
      uri = URI.parse(url.to_s)
      return nil if uri.scheme.nil? || uri.host.nil?
      return nil unless uri.userinfo.nil?  # https://registered.example.com@evil.com

      uri
    rescue URI::InvalidURIError, ArgumentError
      nil
    end

    # "" and "/" are the same resource; a trailing slash is not a different callback.
    def self.normalize_path(path)
      path = path.to_s
      path = "/#{path}" unless path.start_with?('/')
      path = path.chomp('/')
      path.empty? ? '/' : path
    end

    # +pkce+ is the {:code_challenge, :code_challenge_method} the authorize request asked to have
    # bound to this code, or nil.  Binding it here is what lets the token endpoint prove that the
    # client redeeming the code is the one that requested it, without a shared secret.
    def create_request_token(user, callback_url, scope = 'basic',
                             interval = Platform::Config.oauth_request_token_lifetime, pkce = nil)
      token = Platform::Oauth::RequestToken.new
      token.application = self
      token.user = user
      token.callback_url = callback_url
      token.scope = scope

      if pkce
        token.code_challenge        = pkce[:code_challenge]
        token.code_challenge_method = pkce[:code_challenge_method]
      end

      token.generate_key
      token.expire_in(interval)
      token.save!
      token
    end

    # interval defaults to a real lifetime now.  It defaulted to nil, and #expire_in returns
    # immediately on nil, so valid_to was left NULL and #valid_token? -- which only treats a
    # non-NULL valid_to as an expiry -- never expired one.  Every refresh token ever handed out
    # was a permanent credential.  RFC 9700 section 4.14 wants either an expiry or rotation with
    # replay detection; this gem now does both.
    def create_refresh_token(user = nil, scope = 'basic', interval = Platform::Config.oauth_refresh_token_lifetime)
      token = Platform::Oauth::RefreshToken.new
      token.application = self
      token.user = user
      token.scope = scope
      token.generate_key
      token.expire_in(interval)
      token.save!
      token
    end

    def create_client_token(scope, interval = 1.hour)
      token = Platform::Oauth::ClientToken.new
      token.application = self
      token.scope = scope
      token.generate_key
      token.expire_in(interval)
      token.save!
      token
    end

    def invalidate_all_access_tokens(user)
      tokens = Platform::Oauth::AccessToken.where(["application_id = ? and user_id = ?", self.id, user.id])
      tokens.each do |token|
        token.invalidate!
      end
    end

    def create_access_token(user, scope = 'basic', interval = Platform::Config.api_token_lifetime)
      token = Platform::Oauth::AccessToken.new
      token.application = self
      token.user = user
      token.scope = scope
      token.generate_key
      token.expire_in(interval)
      token.save!
      token
    end

    def find_or_create_access_token(user, scope = 'basic', interval = Platform::Config.api_token_lifetime)
      tokens = Platform::Oauth::AccessToken.where(["application_id = ? and user_id = ?", self.id, user.id])
      valid_token = nil
      tokens.each do |token|
        if token.valid_token?(scope) and valid_token.nil?
          valid_token = token
        else
          token.destroy
        end
      end

      valid_token ||= begin
        token = Platform::Oauth::AccessToken.new
        token.application = self
        token.user = user
        token.scope = scope
        token.generate_key
        token.expire_in(interval)
        token.save!
        token
      end

      Platform::ApplicationUser.touch(self, user)
      valid_token
    end

    def admin_link
      "#{DEFAULT_SITE_LINK}/admin/applications/view/#{id}"
    end

    # deprecated
    def self.permissions
      [:no_rate_limit, :grant_type_password, :unlimited_models, :add_without_premium, :trusted,
       :tos_required, :public_client]
    end

    def icon_url
      return Platform::Config.default_app_icon unless icon
      if Platform::Config.site_media_enabled?
        Platform::Config.icon_url(icon)
      else
        icon.url
      end
    end

    def store_icon(file)
      if Platform::Config.site_media_enabled?
        update(:icon => Platform::Config.create_media(file))
      else
        self.icon = Platform::Media::Image.create
        self.icon.write(file, :size => 16)
        self.save
      end
    end

    def logo_url
      return Platform::Config.default_app_logo unless logo
      if Platform::Config.site_media_enabled?
        Platform::Config.logo_url(logo)
      else
        logo.url
      end
    end

    def store_logo(file)
      if Platform::Config.site_media_enabled?
        update(:logo => Platform::Config.create_media(file))
      else
        self.logo = Platform::Media::Image.create
        self.logo.write(file, :size => 75)
        self.save
      end
    end

    def short_description
      return description if description.blank? or description.length < 400
      "#{description[0..400]}..."
    end

    def app_url
      return url if canvas_name.blank?
      "http://#{SITE}/platform/apps/#{canvas_name}"
    end

    def short_name
      return name if name.length < 15
      "#{name[0..15]}..."
    end

    def update_rank!
      total_rank = (rating_count == 0) ? 0 : (rating_sum/rating_count)
      update(:rank => total_rank)
      total_rank
    end

    def developed_by?(dev = Platform::Config.current_developer)
      self.developer == dev
    end

    def rating_count
      @rating_count ||= Platform::Rating.count(:id, :conditions => ["object_type = ? and object_id = ?", self.class.name, self.id])
    end

    def rating_sum
      @rating_sum ||= Platform::Rating.sum(:value, :conditions => ["object_type = ? and object_id = ?", self.class.name, self.id])
    end

    def reset_secret!
      update(:secret => Platform::Helper.generate_key(40)[0,40])
    end

    def authorize_user(user = Platform::Config.current_user)
      Platform::ApplicationUser.touch(self, user)
    end

    def authorized_user?(user = Platform::Config.current_user)
      not Platform::ApplicationUser.where(["application_id = ? and user_id = ?", self.id, user.id]).first.nil?
    end

    def deauthorize_user(user = Platform::Config.current_user)
      invalidate_all_access_tokens(user)
      app_user = Platform::ApplicationUser.for(self, user)
      app_user.destroy if app_user

      # ping the deauthorization url - maybe that should be done in a task
    end

    # grant type password apps should require signature
    def requires_signature?
      false
    end

    def last_monthly_metric
      @last_monthly_metric ||= Platform::MonthlyApplicationMetric.where(["application_id = ?", id]).order('interval desc').first
    end

    def last_total_metric
      @last_total_metric ||= Platform::TotalApplicationMetric.where(["application_id = ?", id]).order('interval desc').first
    end

    def recently_updated_reviews
      @recently_updated_reviews ||= Platform::Rating.where(["object_type = ? and object_id = ?", 'Platform::Application', self.id]).order("updated_at desc").limit(5)
    end

    def recently_updated_discussions
      @recently_updated_discussions ||= Platform::ForumTopic.where(["subject_type = ? and subject_id = ?", 'Platform::Application', self.id]).order("updated_at desc").limit(5)
    end

    ############################################################################
    #### Category Management Methods
    ############################################################################

    def category_names
      categories.collect{|cat| cat.name}.join(", ")
    end

    def add_category(cat)
      cat = Platform::Category.find_by_keyword(cat) if cat.is_a?(String)
      return nil if not cat

      Platform::ApplicationCategory.find_or_create(self, cat)
    end

    def add_categories(catigories)
      catigories.each do |cat|
        add_category(cat)
      end
    end

    def remove_category(cat)
      cat = Platform::Category.find_by_keyword(cat) if cat.is_a?(String)
      return nil if not cat

      app_cat = Platform::ApplicationCategory.find_by_application_id_and_category_id(self.id, cat.id)
      app_cat.destroy if app_cat
    end

    def remove_categories(categories)
      categories.each do |cat|
        remove_category(cat)
      end
    end

    def self.featured_for_category(category, page = 1, per_page = 20)
      return [] if category.nil?
      paginate(:conditions => ["platform_applications.state='approved' and platform_application_categories.category_id = ? and platform_application_categories.featured = ?", category.id, true],
              :joins => "inner join platform_application_categories on platform_application_categories.application_id = platform_applications.id",
              :order => "platform_application_categories.position asc", :page => page, :per_page => per_page)
    end

    def self.regular_for_category(category, page = 1, per_page = 20)
      return [] if category.nil?
      paginate(:conditions => ["platform_applications.state='approved' and platform_application_categories.category_id = ? and (platform_application_categories.featured is null or platform_application_categories.featured = ?)", category.id, false],
              :joins => "inner join platform_application_categories on platform_application_categories.application_id = platform_applications.id",
              :order => "platform_application_categories.position asc", :page => page, :per_page => per_page)
    end

    def versioned_name
      @versioned_name ||= begin
        "#{name} #{version}"
      end
    end

    def oauth_url
      protocol = Platform::Config.env == "development" ? 'http' : 'https'
      "#{protocol}://#{Platform::Config.site_base_url}/platform/oauth/authorize?client_id=#{key}&response_type=token&display=web&redirect_url=#{CGI.escape(callback_url || '')}"
    end

  private

    def generate_keys
      self.key = Platform::Helper.generate_key(40)[0,40] if key.nil?
      self.secret = Platform::Helper.generate_key(40)[0,40] if secret.nil?
    end

  end # class Application
end # module Platform
