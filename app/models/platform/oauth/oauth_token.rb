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

class Platform::Oauth::OauthToken < ActiveRecord::Base
  set_table_name :platform_oauth_tokens

  belongs_to :application, :class_name => "Platform::Application"
  belongs_to :user, :class_name => Platform::Config.user_class_name, :foreign_key => :user_id

  validates_uniqueness_of :token
  validates_presence_of   :application
  validates_presence_of   :token

  def valid_token?(requested_scope = nil)
    return false if invalidated_at != nil
    return false if valid_to and Time.now > valid_to
    return false if requested_scope and requested_scope != self.scope
    true
  end

  def invalidated?
    invalidated_at != nil
  end

  def invalidate
    self.invalidated_at = Time.now
  end

  def invalidate!
    invalidate
    save!
  end

  def authorized?
    authorized_at && !invalidated?
  end

  def authorize
    self.authorized_at = Time.now
  end

  def authorize!
    authorize
    save!
  end

  def expire_in(interval)
    return if interval.nil?
    self.valid_to = (Time.now + interval)
  end
  alias expire_in= expire_in

  def expire_in!(interval)
    expire_in(interval)
    save!
  end

  def generate_key
    self.token = Platform::Helper.generate_key(40)[0,40]
  end

  def to_json(options={})
    hash = {
      :access_token => token,
      :expires_in   => (valid_to.to_i - Time.now.to_i),
    }.to_json(options)
  end

end
