# ApplicationRecord doesn't exist in Rails 3.2, it was added in Rails 5.0
# This is a shim for engines/gems that expect it to exist
class ApplicationRecord < ActiveRecord::Base
  self.abstract_class = true
end
