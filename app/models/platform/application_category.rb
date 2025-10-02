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
# Table name: platform_application_categories
#
#  id             :integer          not null, primary key
#  featured       :boolean
#  position       :integer
#  created_at     :datetime
#  updated_at     :datetime
#  application_id :integer          not null
#  category_id    :integer          not null
#
# Indexes
#
#  idx_platform_app_categories_on_cat_and_app            (category_id,application_id)
#  index_platform_application_categories_on_category_id  (category_id)
#
module Platform
  class ApplicationCategory < ApplicationRecord

    belongs_to :category
    belongs_to :application

    def self.find_or_create(app, cat)
      find_by_application_id_and_category_id(app.id, cat.id) || create(:application => app, :category => cat)
    end

  end # class ApplicationCategory
end # module Platform
