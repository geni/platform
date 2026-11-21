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

# The device authorization grant's two codes, RFC 8628.
#
# One row carries both: #token is the device_code the client polls with, and #secret is the
# user_code the human types in.  They are the same record because they name the same pending
# authorization, and keeping them together is what lets the poll see the moment the user approves.
#
# Why this grant exists here at all: a client that cannot receive a redirect cannot use the
# authorization code flow.  The usual answer for a CLI is a loopback redirect on 127.0.0.1
# (RFC 8252), and ours is unavailable -- the edge WAF rejects any request whose redirect_uri
# contains "localhost" or "127.0.0.1", so the authorize call never reaches Rails.  The device
# grant sends no redirect_uri at all, which is why it works where loopback does not.
module Platform
  module Oauth
    class DeviceCode < Oauth::OauthToken

      validates_presence_of :secret

      # The alphabet the user_code is drawn from, and the reason it is not A-Z0-9.
      #
      # No O or 0, no I, L or 1: a user_code is read off one screen and typed into another, often from
      # a phone, and those are the pairs people transcribe wrongly.  RFC 8628 section 6.1 asks for
      # exactly this consideration.  20 characters over 8 positions is a little over 34 bits, which
      # the same section calls adequate *provided* the verification endpoint is rate limited -- so the
      # limiter in Platform::OauthController#device is not a nicety, it is what makes a code this
      # short safe to use.
      USER_CODE_ALPHABET = 'BCDFGHJKMNPQRSTVWXYZ'.freeze
      USER_CODE_LENGTH   = 8
      USER_CODE_GROUP    = 4

      # What the client polls with.
      def device_code
        client_token
      end

      # What the human types.  Stored and compared in its normalised form; #user_code_for_display
      # adds the hyphen back.
      def user_code
        secret
      end

      def user_code_for_display
        self.class.format_user_code(secret)
      end

      def generate_user_code
        self.secret = self.class.unique_user_code
      end

      # Normalise before storing or comparing: the code is displayed as WDJB-MJHT but a user may type
      # it lowercase, without the hyphen, or with spaces, and all of those mean the same code.
      def self.normalize_user_code(candidate)
        candidate.to_s.upcase.gsub(/[^A-Z0-9]/, '')
      end

      def self.format_user_code(code)
        code.to_s.scan(/.{1,#{USER_CODE_GROUP}}/).join('-')
      end

      def self.random_user_code
        (1..USER_CODE_LENGTH).map { USER_CODE_ALPHABET[SecureRandom.random_number(USER_CODE_ALPHABET.length), 1] }.join
      end

      # Collisions matter more here than for a 40-character token: the space is small enough that a
      # duplicate live code would let one user's approval answer another client's poll.
      def self.unique_user_code
        10.times do
          candidate = random_user_code
          return candidate if pending_for_user_code(candidate).nil?
        end

        raise 'could not generate an unused user_code'
      end

      # The pending authorization a user_code names, or nil.
      #
      # Scoped to rows that are still usable, so a recycled code cannot resurrect a finished one: an
      # expired or invalidated row is not a match, and neither is one already exchanged.
      def self.pending_for_user_code(candidate)
        candidate = normalize_user_code(candidate)
        return nil if candidate.empty?

        found = first_pending(candidate)
        return nil if found.nil?
        return nil unless found.valid_token?
        return nil unless found.exchanged_at.nil?

        found
      end

      # Separated so the host application can override the query without reimplementing the guards
      # above.
      #
      # The branches this came from spell it `find(:first, conditions:, order:)`, because Rails 2.3
      # has no +where+.  Rails 8 removed that form of #find entirely -- it takes ids now -- so the
      # old spelling did not fail loudly, it looked up a record with the id :first and raised
      # RecordNotFound on every call.
      def self.first_pending(normalized)
        where('secret = ? and invalidated_at is null', normalized).order(id: :desc).first
      end

      # Has the user approved this yet?  #authorized? comes from the base class and is what the poll
      # waits on.
      def pending?
        !authorized? && valid_token? && exchanged_at.nil?
      end

    end
  end
end
