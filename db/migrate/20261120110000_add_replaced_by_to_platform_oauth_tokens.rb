class AddReplacedByToPlatformOauthTokens < ActiveRecord::Migration[8.0]
  # Records which refresh token a refresh token was exchanged for, so that a second presentation of
  # an already-redeemed one can be answered with that same replacement instead of revoking the
  # family.
  #
  # RFC 9700 section 4.14.2 asks for family revocation when a refresh token is replayed, because two
  # presentations mean two holders and the server cannot tell which one is the attacker.  It does not
  # ask for a zero-length detection window, and Okta's refresh token rotation ships exactly this
  # allowance as its grace period: inside the window the caller is handed the same replacement,
  # outside it the family goes.
  #
  # The window needs this column to be worth having.  Minting a *fresh* refresh token for an
  # in-window retry would leave two live families -- one caller keeps each, and the one nobody
  # writes down stays valid for the whole 90-day refresh lifetime with no holder watching it.
  # Handing back the recorded replacement converges every caller on one family instead, which is
  # what a client running several processes behind one credential file needs.
  #
  # It is also what makes the exchange claim safe to lose.  RefreshToken#claim_for_exchange! flips
  # exchanged_at from NULL conditionally, and the loser of that race reads the winner's replacement
  # out of this column rather than minting its own.
  #
  # No index: the column is only ever read from a row already located by its own token.
  #
  # Nullable, and null is the normal state -- it is set only on the one row that was exchanged.  A
  # row carrying exchanged_at but no replaced_by_id predates this migration, and
  # #grace_period_replacement treats that as a replay, so existing rows keep the behaviour they
  # already had.
  #
  # Instance methods rather than `def self.up` / `def self.down`, which the sibling migrations on
  # this branch still use: the migrator calls #up on the migration *instance*, so a class method of
  # that name is never reached.
  def up
    add_column :platform_oauth_tokens, :replaced_by_id, :integer, limit: 8
  end

  def down
    remove_column :platform_oauth_tokens, :replaced_by_id
  end
end
