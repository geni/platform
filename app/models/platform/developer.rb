#--
# Copyright (c) 2010-2012 Michael Berkovich
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
#
#-- Platform::Developer Schema Information
#
# Table name: platform_developers
#
#  id            INTEGER         not null, primary key
#  user_id       integer(8)      not null
#  name          varchar(255)    not null
#  about         text            
#  url           varchar(255)    
#  email         varchar(255)    
#  phone         varchar(255)    
#  created_at    datetime        
#  updated_at    datetime        
#
# Indexes
#
#  index_platform_developers_on_user_id    (user_id) 
#
#++

class Platform::Developer < ActiveRecord::Base
  self.table_name = :platform_developers

  belongs_to :user, :class_name => Platform::Config.user_class_name, :foreign_key => :user_id
  
  has_many :application_developers, :class_name => "Platform::ApplicationDeveloper", :order => "updated_at desc"
  has_many :applications, :class_name => "Platform::Application", :through => :application_developers
  
  has_many :developer_roles, :class_name => "Platform::DeveloperRole"
  has_many :roles, :class_name => "Platform::Role", :through => :developer_roles

  def self.for(user)
    return nil unless user and user.id 
    return nil if Platform::Config.guest_user?(user)
    return user if user.is_a?(Platform::Developer)
    find_by_user_id(user.id)
  end
  
  def self.find_or_create(user)
    dev = find(:first, :conditions => ["user_id = ?", user.id])
    dev = create(:user => user, :name => Platform::Config.user_name(user), :email => Platform::Config.user_email(user)) unless dev
    dev
  end
  
  def app_options
    @app_options ||= applications.collect{|app| [app.name, app.id]}
  end
  
end
