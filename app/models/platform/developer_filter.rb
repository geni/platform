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
# Table name: wf_filters
#
#  id               :integer          not null, primary key
#  data             :text
#  model_class_name :string
#  name             :string
#  type             :string
#  created_at       :datetime
#  updated_at       :datetime
#  user_id          :integer
#
# Indexes
#
#  index_wf_filters_on_user_id  (user_id)
#
module Platform
  class DeveloperFilter < BaseFilter

    # Every other filter in the gem can leave this to will_filter, which derives the filtered
    # model from the filter's own class name: it strips "Filter" and constantizes the rest.  For
    # this one that yields Platform::Developer -- the *module*; the model is
    # Platform::Developer::Developer -- and WillFilter::Filter#initialize only checks that the
    # name resolves to something, not that what it resolved to is a model.  So it quietly filtered
    # against a module.
    #
    # Platform::Developer::Developer.filter passes the model itself (will_filter's #filter does
    # `filter_class.new(self)`) and so never reaches the fallback below.  The fallback is what
    # makes a bare DeveloperFilter.new correct on its own.
    #
    # Note the nil check rather than a default argument.  ActiveRecord::Base.new is declared
    # `new(attributes = nil)` and passes that through, so #initialize is always called with one
    # argument and a default on the parameter would never fire.
    def initialize(model_class = nil)
      super(model_class || Platform::Developer::Developer)
    end

  end # class DeveloperFilter
end # module Platform
