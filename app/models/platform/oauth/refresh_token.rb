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

      # #now_in_database_timezone has moved to Platform::Oauth::OauthToken, which needs it for
      # .live_tokens_for.  It is inherited, so every call here and in this gem's tests still
      # resolves.

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

      # Claim this token for exchange, recording what replaced it.  Answers false if somebody else
      # claimed it first, in which case the caller has not been given anything and must not mint a
      # family of its own.
      #
      # A conditional UPDATE rather than #exchanged!, because #replayed? is a read and the write is a
      # separate statement: two requests presenting the same token can both pass the check before
      # either writes.  With a plain save! both then "succeed" with the grace period switched off, and
      # the family nobody writes down keeps working, unwatched, for the whole refresh lifetime.
      # Whoever flips exchanged_at from NULL wins; the loser is told so and is handled as a retry.
      #
      # Raw SQL because the branches this ships on span Rails 2.3 to Rails 8, and the conditional
      # update does not have one spelling across them: 2.3 has no #where, and modern #update_all takes
      # no conditions argument.  #connection.update answers the affected row count everywhere.
      def claim_for_exchange!(replacement)
        table = self.class.table_name
        now   = self.class.connection.quoted_date(self.class.now_in_database_timezone)

        claimed = self.class.connection.update(<<-SQL) == 1
          UPDATE #{table}
             SET exchanged_at   = '#{now}',
                 invalidated_at = '#{now}',
                 replaced_by_id = #{replacement.id.to_i}
           WHERE id = #{id.to_i}
             AND exchanged_at IS NULL
        SQL

        # Either way the row on disk is now authoritative and this object is stale: on a win it carries
        # what we just wrote, and on a loss it carries the winner's exchange, which is what decides
        # whether the loser is inside the grace period.
        reload
        claimed
      end

      # The replacement issued when this token was exchanged, if that replacement is still live.
      #
      # Its *value* is not recoverable and this is not an attempt to recover it: refresh tokens are
      # digested at rest, so #client_token answers nil for any row read back from the database.  What
      # matters here is its liveness, which is the only honest signal that the grant behind this token
      # still stands.  If the user deauthorized the application, or an admin revoked it, or a family
      # revocation swept through, the replacement is invalidated too -- and then an in-window
      # presentation is not a retry worth honouring, it is a client using a withdrawn credential.
      def live_replacement
        return nil if replaced_by_id.nil?

        replacement = Platform::Oauth::RefreshToken.find_by_id(replaced_by_id)
        replacement if replacement && replacement.valid_token?
      end

      # Is this presentation of an already-exchanged token a retry rather than a replay?
      #
      # A client that never received our reply -- a dropped connection, a killed process, a laptop
      # asleep mid-request -- holds only the token it started with, and presenting it again is a retry.
      # So is the second of two processes sharing one credential file.  RFC 9700 section 4.14.2 asks for
      # family revocation on replay and leaves the detection window to the implementation; Okta's
      # refresh token rotation ships that allowance as its grace period, and this is the same thing.
      #
      # A zero period restores strict one-presentation detection.
      def grace_period_retry?
        return false if exchanged_at.nil?

        period = Platform::Config.oauth_refresh_token_grace_period
        return false unless period > 0
        return false if Time.now - exchanged_at > period

        not live_replacement.nil?
      end

      # Was this token already redeemed, outside any window in which that could be a retry?
      #
      # Not simply "is it invalidated": a refresh token is also invalidated when the user
      # deauthorizes the application, when an admin revokes it, and when a family revocation sweeps
      # it up.  Those are ordinary revocations, and treating them as replays would report an attack
      # every time a client used a credential that had been withdrawn.  Only a token that was
      # *exchanged* and then presented again implies two holders -- and only outside the grace period,
      # where a second presentation stops being explicable as a retry.  See #grace_period_retry?.
      def replayed?
        return false if exchanged_at.nil?

        not grace_period_retry?
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
