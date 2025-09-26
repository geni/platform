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
# Table name: platform_application_metrics
#
#  id                :integer          not null, primary key
#  active_user_count :integer
#  interval          :datetime
#  new_user_count    :integer
#  type              :string
#  created_at        :datetime
#  updated_at        :datetime
#  application_id    :integer
#
# Indexes
#
#  idx_platform_application_metrics_on_app_and_interval  (application_id,interval)
#
module Platform
  class TotalApplicationMetric < ApplicationMetric

    def self.calculate_metric(app, interval)
      metric = find_or_create(app, interval)

      # TODO: convert to PlatformApplicationUser.count
      results = execute_query("select count(user_id) as count from platform_application_users where application_id=#{app.id} and created_at <= '#{interval}'");
      metric.new_user_count = results.first["count"]
      metric.active_user_count = results.first["count"]

      metric.save
    end

    def user_count
      new_user_count
    end

  end # class TotalApplicationMetric
end # module Platform
