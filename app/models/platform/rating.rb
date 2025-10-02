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
# Table name: platform_ratings
#
#  id          :integer          not null, primary key
#  comment     :text
#  object_type :string
#  value       :integer
#  created_at  :datetime
#  updated_at  :datetime
#  object_id   :integer
#  user_id     :bigint           not null
#
# Indexes
#
#  index_platform_ratings_on_object_type_and_object_id  (object_type,object_id)
#  index_platform_ratings_on_user_id                    (user_id)
#
module Platform
  class Rating < ApplicationRecord

    belongs_to :user, :class_name => Platform::Config.user_class_name, :foreign_key => :user_id
    belongs_to :object, :polymorphic => true

    def self.for(app, user=Platform::Config.current_user)
      where('object_type = ? and object_id = ? and user_id = ?', app.class.name, app.id, user.id).first
    end

    def self.find_or_create(app, user=Platform::Config.current_user)
      self.for(app, user) || create(:object => app, :user => user)
    end

    def toHTML
      return '' unless comment
      Platform.escape_html(comment).gsub("\n", "<br>")
    end

  end # class Rating
end # module Platform
