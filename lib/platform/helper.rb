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

require 'openssl'
require 'base64'
require 'securerandom'

module Platform::Helper

  # Retained because Platform::Application#generate_keys and #reset_secret! have always built
  # client keys and secrets this way, and those are stored values -- changing the generator would
  # not re-issue anything, it would only make new rows look different from old ones.
  #
  # Note what it does: it base64-encodes random bytes and then *strips* every character base64
  # produced that is not a word character ("+", "/", "=" and the line breaks).  Callers truncate
  # the survivors to a fixed width, so how many characters you get back depends on how many
  # stripped characters the encoding happened to contain, and the resulting alphabet is skewed.
  # 40 characters of [A-Za-z0-9] is ~238 bits either way, so this was never weak -- but prefer
  # generate_token below for anything new.
  def self.generate_key(size=32)
    Base64.encode64(OpenSSL::Random.random_bytes(size)).gsub(/\W/, '')
  end

  # Bearer tokens and authorization codes.  Fixed length, no truncation, no stripping, and the
  # same [A-Za-z0-9] alphabet the 40-character tokens already in platform_oauth_tokens use, so
  # clients that assume an alphanumeric token keep working.
  def self.generate_token(length=40)
    SecureRandom.alphanumeric(length)
  end

  # SHA-256, urlsafe-base64, unpadded: 43 characters, which fits the varchar(50) token column
  # without a migration.  Used to keep tokens out of the database in the clear -- see
  # Platform::Oauth::OauthToken.
  def self.token_digest(raw_token)
    Base64.urlsafe_encode64(OpenSSL::Digest::SHA256.digest(raw_token.to_s)).delete('=')
  end

  # Constant-time string comparison, for client secrets and other presented credentials.
  #
  # Hashing both sides first is what lets this run in constant time even when the two strings are
  # different lengths: the digests are always 32 bytes, so the loop below never short-circuits on
  # a length check and never leaks the length of the expected value.  The bytesize comparison at
  # the end is outside the secret-dependent path -- it only rejects a (cryptographically
  # impossible) digest collision between strings of different lengths.
  def self.secure_compare(presented, expected)
    presented = presented.to_s
    expected  = expected.to_s
    return false if presented.empty? || expected.empty?

    presented_digest = OpenSSL::Digest::SHA256.digest(presented)
    expected_digest  = OpenSSL::Digest::SHA256.digest(expected)

    result = 0
    presented_digest.bytesize.times do |i|
      result |= presented_digest.getbyte(i) ^ expected_digest.getbyte(i)
    end

    result == 0 && presented.bytesize == expected.bytesize
  end

  # The serialized origin ("https://host:port") of a URL, or nil if it has no host.  Used to
  # decide the target origin of an xd postMessage and to compare registered app origins.
  def self.origin_of(url)
    uri = URI.parse(url.to_s)
    return nil if uri.host.blank?

    origin = "#{uri.scheme}://#{uri.host}"
    origin << ":#{uri.port}" unless uri.port.nil? || uri.port == uri.default_port
    origin
  rescue URI::InvalidURIError, ArgumentError
    nil
  end

end
