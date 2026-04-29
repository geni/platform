# Be sure to restart your server when you modify this file.

# Your secret key for verifying the integrity of signed cookies.
# If you change this key, all old signed cookies will become invalid!
# Make sure the secret is at least 30 characters and all random,
# no regular words or you'll be exposed to dictionary attacks.

# Rails 3.0 uses ActionController::Base.cookie_verifier_secret
# Rails 3.1+ uses PlatformGem::Application.config.secret_token
if defined?(PlatformGem::Application) && defined?(Rails::VERSION) && Rails::VERSION::MAJOR >= 3 && Rails::VERSION::MINOR >= 1
  PlatformGem::Application.config.secret_token = 'ba7c18a3e1838e756edb38e2eb7dc9fc090b8d08a1e53ccce49de2fecfbfee3b6dce4d0eb55b08ce50adb4722d1d2e7d4efbead676712e28fceaa5785c1e8e32'
elsif defined?(ActionController::Base) && ActionController::Base.respond_to?(:cookie_verifier_secret=)
  ActionController::Base.cookie_verifier_secret = 'ba7c18a3e1838e756edb38e2eb7dc9fc090b8d08a1e53ccce49de2fecfbfee3b6dce4d0eb55b08ce50adb4722d1d2e7d4efbead676712e28fceaa5785c1e8e32'
end
