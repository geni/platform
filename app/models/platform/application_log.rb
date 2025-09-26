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
# Table name: platform_application_logs
#
#  id             :integer          not null, primary key
#  action         :string
#  controller     :string
#  country        :string
#  data           :text
#  duration       :integer
#  event          :string
#  host           :string
#  ip             :string
#  request_method :string
#  user_agent     :string
#  created_at     :datetime
#  updated_at     :datetime
#  application_id :integer
#  user_id        :integer
#
# Indexes
#
#  idx_platform_application_logs_on_app_and_created_at  (application_id,created_at)
#
module Platform
  class ApplicationLog < ApplicationRecord
    self.table_name = :platform_application_logs

    belongs_to :user, :class_name => Platform::Config.user_class_name, :foreign_key => :user_id
    belongs_to :application

    serialize :data, :type => Object, :coder => YAML

  end # class ApplicationLog
end # module Platform
