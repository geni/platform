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

class Platform::Oauth::OauthToken < ActiveRecord::Base
  self.table_name = "platform_oauth_tokens"

  belongs_to :application, :class_name => "Platform::Application"
  belongs_to :user, :class_name => Platform::Config.user_class_name, :foreign_key => :user_id

  validates_uniqueness_of :token
  validates_presence_of   :application
  validates_presence_of   :token

  attr_accessible :application, :application_id, :user, :user_id, :token, :scope, :callback_url, :expire_in

  # #nil?, not `!= nil`.  On activesupport 3.1 and 3.2 invalidated_at is an
  # ActiveSupport::TimeWithZone, and `TimeWithZone != nil` routes through #<=> ->
  # #compare_with_coercion -> nil.to_datetime and raises NoMethodError.  So asking whether an
  # *invalidated* token is valid blew up rather than answering false -- latent until something
  # called #valid_token? on a token that had been invalidated, which
  # RefreshToken#live_replacement now does on every grace-period check.
  def valid_token?(requested_scope = nil)
    return false unless invalidated_at.nil?
    return false if valid_to and Time.now > valid_to
    return false if requested_scope and requested_scope != self.scope
    true
  end

  def invalidated?
    !invalidated_at.nil?
  end

  def invalidate
    self.invalidated_at = Time.now
  end

  def invalidate!
    invalidate
    save!
  end

  def authorized?
    authorized_at && !invalidated?
  end

  def authorize
    self.authorized_at = Time.now
  end

  def authorize!
    authorize
    save!
  end

  def expire_in(interval)
    return if interval.nil?
    self.valid_to = (Time.now + interval)
  end
  alias expire_in= expire_in

  def expire_in!(interval)
    expire_in(interval)
    save!
  end

  ##########################################################################
  #### Token values
  ####
  #### The cleartext token is what the client gets; what we store may be a digest of it.  Those
  #### two were the same string for the lifetime of this table, so read #client_token below
  #### before handing anything back to a client.
  ##########################################################################

  # The cleartext token, available only on a record this process generated or just authenticated.
  # Nil on a record loaded from the database whose type is stored as a digest -- which is the
  # whole point of storing a digest.
  attr_reader :raw_token

  # Is this token type stored as a digest rather than in the clear?
  #
  # Request and refresh tokens are: both are minted fresh and handed straight back, so nothing
  # ever needs to recover the cleartext.  Access and client tokens are not, because
  # Platform::Application#find_or_create_access_token *reuses* a stored access token and returns
  # it to the client, and a digest cannot be turned back into the token that produced it.  Hashing
  # those two means giving up that reuse -- see the note in config/platform/config.yml.
  def self.store_digest?
    Platform::Config.oauth_hashed_token_types.include?(name)
  end

  # Look up a token by the value a client presented.
  #
  # Tries the digest first, then -- while the switch allows it -- the cleartext, which is how rows
  # written before hashing was turned on keep working.  Any row found by cleartext is rewritten as
  # a digest on the spot, so the table converts itself as clients call in and the switch can be
  # turned off once the longest token lifetime has elapsed.
  #
  # Digests are 43 characters and generated tokens are 40, so the two lookups cannot collide.
  def self.find_by_presented_token(presented)
    presented = presented.to_s
    return nil if presented.empty?

    if (found = find_by_token(Platform::Helper.token_digest(presented)))
      found.instance_variable_set(:@raw_token, presented)
      return found
    end

    return nil unless Platform::Config.oauth_allow_cleartext_token_lookup?

    # Refuse to resolve a digest that was presented as though it were a token.
    #
    # The cleartext lookup below matches the `token` column verbatim, and for a digested type that
    # column *holds a digest* -- so without this guard, presenting the stored digest authenticates
    # as its owner.  That turns read access to platform_oauth_tokens (a replica, a backup, a
    # slow-query log) into the ability to act as any member, which is the one thing digesting the
    # column was supposed to prevent.  It compounds too: #upgrade_stored_token_to_digest! below
    # would then rewrite the row as a digest of the digest, so the real token stops working.
    #
    # Reaching that state needs a digest to escape to a caller, which is a bug rather than a
    # designed path -- but it is a bug this gem has shipped more than once, every time something
    # read #token where it meant #client_token.  So the lookup refuses the shape rather than
    # trusting every caller to be correct.
    #
    # Only for a digested type: a type stored in the clear has no digest in its column for this to
    # protect, and gating it this way keeps a cleartext token that happens to be the width of a
    # digest resolvable.
    return nil if store_digest? && Platform::Helper.token_digest_shaped?(presented)

    found = find_by_token(presented)
    return nil if found.nil?

    found.instance_variable_set(:@raw_token, presented)
    found.upgrade_stored_token_to_digest!
    found
  end

  # Rewrite a cleartext row as a digest.  Skips validation deliberately: validates_uniqueness_of
  # would cost a query per call and the value being written is a digest of a value that already
  # satisfied the unique index.
  def upgrade_stored_token_to_digest!
    return false unless self.class.store_digest?
    return false if raw_token.nil?

    update_attribute(:token, Platform::Helper.token_digest(raw_token))
    true
  end

  def generate_key
    raw = Platform::Helper.generate_token(40)

    @raw_token = raw
    self.token = self.class.store_digest? ? Platform::Helper.token_digest(raw) : raw

    raw
  end

  # The value to hand back to a client.  Falls back to the stored value, which is correct for the
  # token types that are not digested; for a digested type with no cleartext in hand this is nil
  # rather than the digest, so a caller that returns it hands back nothing instead of handing back
  # something that looks like a token but can never authenticate.
  def client_token
    raw_token || (self.class.store_digest? ? nil : token)
  end

  def to_json(options={})
    hash = {
      :access_token => client_token,
      :expires_in   => (valid_to.to_i - Time.now.to_i),
    }.to_json(options)
  end

  # The clock reading to write into, or compare against, a timestamp column from raw SQL.
  #
  # ActiveRecord::Base.default_timezone decides how these columns are read back, so it has to decide
  # how they are written.  Rails 2.3's #quoted_date is `value.to_s(:db)` and converts nothing, so
  # handing it Time.now.utc on an app configured :local -- which both Geni applications are -- stores
  # a clock reading hours ahead of local, and RefreshToken#grace_period_retry? then measures a
  # *negative* age and calls every second presentation a retry, forever.  Modern #quoted_date does
  # convert, so passing an already-correct Time is right on every branch this ships on.
  #
  # Lives on the base class because .live_tokens_for compares against it too, and
  # RefreshToken#claim_for_exchange! -- where this was first needed -- inherits it.
  def self.now_in_database_timezone
    # Rails 7.0 moved this off ActiveRecord::Base onto the ActiveRecord module and 7.1 removed the
    # old reader, so ask whichever one this Rails has.  2.3 answers through Base; rails-8.0.x needs
    # the module, and asking keeps this method identical on every branch.
    zone = if ActiveRecord.respond_to?(:default_timezone)
             ActiveRecord.default_timezone
           else
             ActiveRecord::Base.default_timezone
           end

    zone == :utc ? Time.now.utc : Time.now.getlocal
  end

  # How many rows .revoke_all_for pulls into memory at a time.
  REVOKE_BATCH_SIZE = 500

  # Every live token this application holds for this user, of every type.
  #
  # find_by_sql rather than a scope or #find(:first, :conditions => ...): the finder and relation
  # APIs for a multi-row conditional query are different on every Rails branch this gem supports,
  # and find_by_sql is the one that is the same on all of them.  It still instantiates through STI,
  # so the rows come back as the right subclasses and their callbacks fire.
  #
  # Expired rows are excluded, which the name always implied and the query did not do.  Refresh
  # tokens were permanent credentials until this gem started setting valid_to, so production holds
  # millions of unexpiring rows -- 4.3M on one application and member alone -- and every one of them
  # answered this query.  An expired token cannot be redeemed, so revoking it buys nothing and
  # loading it costs everything.
  #
  # The limit is what keeps that bounded even so: a caller must say how many rows it is prepared to
  # instantiate.
  def self.live_tokens_for(application_id, user_id, limit = nil)
    sql  = "SELECT * FROM #{table_name}" \
           " WHERE invalidated_at IS NULL" \
           " AND (valid_to IS NULL OR valid_to > ?)" \
           " AND application_id = ?"
    args = [now_in_database_timezone, application_id]

    if user_id.nil?
      sql << " AND user_id IS NULL"
    else
      sql << " AND user_id = ?"
      args << user_id
    end

    sql << " LIMIT #{limit.to_i}" unless limit.nil?

    find_by_sql([sql] + args)
  end

  # Invalidate every live token this application holds for this user.
  #
  # Each row is invalidated through #invalidate! rather than in one UPDATE on purpose.  The host
  # app hangs after_save on this model to flush the memcached entry behind
  # Application#find_or_create_access_token; a bulk UPDATE would leave that cache serving an
  # access token whose invalidated_at it cannot see, which would make the revocation a no-op for
  # exactly the token type that matters most.
  #
  # In batches, because the row counts here are not small and this runs inside a request.
  # RefreshToken#replay! is the caller, so a single replayed refresh token used to decide how many
  # ActiveRecord objects one process would build: 4.3M for the worst application and member in
  # production, 205k for the next.  That is an out-of-memory kill reachable by presenting one token
  # twice.  Each pass stamps invalidated_at, so the next query no longer sees those rows and the
  # loop drains without an offset.
  def self.revoke_all_for(application_id, user_id)
    revoked = 0

    loop do
      batch = live_tokens_for(application_id, user_id, REVOKE_BATCH_SIZE)
      break if batch.empty?

      batch.each { |token| token.invalidate! }
      revoked += batch.size

      break if batch.size < REVOKE_BATCH_SIZE
    end

    revoked
  end

end
