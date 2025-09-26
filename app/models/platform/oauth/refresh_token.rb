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
# Table name: platform_oauth_tokens
#
#  id             :integer          not null, primary key
#  authorized_at  :datetime
#  callback_url   :string
#  invalidated_at :datetime
#  scope          :string
#  secret         :string(50)
#  token          :string(50)
#  type           :string
#  valid_to       :datetime
#  verifier       :string(20)
#  created_at     :datetime
#  updated_at     :datetime
#  application_id :integer
#  user_id        :bigint
#
# Indexes
#
#  index_platform_oauth_tokens_on_token  (token) UNIQUE
#
module Platform
  module Oauth
    class RefreshToken < Oauth::OauthToken

      def exchange!(params={})
        if user
          token = application.create_access_token(user, scope)
        else
          token = application.create_client_token(scope)
        end

        invalidate!
        token
      end

      def redirect_url
        callback_url
      end

    end # class RefreshToken
  end # module Oauth
end # module Platform
