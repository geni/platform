# Set TR8N root early, before tr8n tries to load config
# The tr8n gem rails-3.1.x branch needs this set before it initializes
if defined?(Tr8n) && defined?(Tr8n::Config)
  # Force tr8n to use the correct root path
  module Tr8n
    class Config
      class << self
        def root
          Rails.root.to_s
        end
      end
    end
  end
end
