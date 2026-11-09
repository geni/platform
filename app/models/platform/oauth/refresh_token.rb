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

        exchanged!
        token
      end

      # Mark this token as redeemed and invalidate it.  One step, because the two facts have to stay
      # consistent: #replayed? reads both.
      def exchanged!
        self.exchanged_at = Time.now
        invalidate
        save!
      end

      # Was this token already redeemed once?
      #
      # Not simply "is it invalidated": a refresh token is also invalidated when the user
      # deauthorizes the application, when an admin revokes it, and when a family revocation sweeps
      # it up.  Those are ordinary revocations, and treating them as replays would report an attack
      # every time a client used a credential that had been withdrawn.  Only a token that was
      # *exchanged* and then presented again implies two holders.
      def replayed?
        not exchanged_at.nil?
      end

      # A refresh token presented after it has already been exchanged.
      #
      # Refresh tokens rotate: exchanging one invalidates it and issues a replacement.  So a second
      # presentation of a redeemed token means two parties hold it, and we cannot tell which of them
      # is the legitimate client -- the attacker may well have redeemed it first and be holding the
      # valid replacement.  RFC 9700 section 4.14.2 says to revoke the whole family rather than
      # guess, which costs the real client a re-authorization and costs the attacker the access they
      # stole.
      def replay!
        Platform::Logger.error(
          "OAUTH_REFRESH_TOKEN_REPLAY app=#{application_id} user=#{user_id.inspect} token_id=#{id} " \
          "invalidated_at=#{invalidated_at} - revoking all tokens for this application and user"
        )

        Platform::Oauth::OauthToken.revoke_all_for(application_id, user_id)
      end

      def redirect_url
        callback_url
      end

    end # class RefreshToken
  end # module Oauth
end # module Platform
