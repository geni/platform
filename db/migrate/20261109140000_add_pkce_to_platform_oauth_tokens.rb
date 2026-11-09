class AddPkceToPlatformOauthTokens < ActiveRecord::Migration[4.2]
  # PKCE (RFC 7636) binds an authorization code to the client that requested it, without needing
  # a shared secret.  The client sends a code_challenge with the authorize request; we store it on
  # the request token here, and the token endpoint will only exchange that code for a client that
  # can present the code_verifier the challenge was derived from.
  #
  # This is what lets a public client -- a desktop, mobile or in-browser app, which cannot keep a
  # client_secret -- still prove it owns the code it is redeeming.
  #
  # 128 characters because RFC 7636 section 4.1 caps a code_verifier at 128, and the "plain"
  # method (which we do not accept, but which sizes the column) makes the challenge the verifier
  # itself.  An S256 challenge is 43 characters.
  # exchanged_at records that a refresh token was redeemed, as opposed to invalidated for any of
  # the other reasons (the user deauthorized the app, an admin revoked it, the whole family was
  # revoked).  Replay detection needs that distinction: presenting a token that was *redeemed*
  # means two parties hold it and the family has to go, while presenting one that was merely
  # revoked is just a client using a credential it no longer has.  Keying off invalidated_at
  # alone would turn every ordinary revocation into a reported replay.
  def self.up
    add_column :platform_oauth_tokens, :code_challenge,        :string, :limit => 128
    add_column :platform_oauth_tokens, :code_challenge_method, :string, :limit => 10
    add_column :platform_oauth_tokens, :exchanged_at,          :timestamp
  end

  def self.down
    remove_column :platform_oauth_tokens, :exchanged_at
    remove_column :platform_oauth_tokens, :code_challenge_method
    remove_column :platform_oauth_tokens, :code_challenge
  end
end
