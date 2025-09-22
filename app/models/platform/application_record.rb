module Platform
  class ApplicationRecord < ActiveRecord::Base
    self.abstract_class = true

    # Used by acts_as_state_machine. Removed in Rails 3.2
    def self.write_inheritable_attribute(attr, value)
      class_attribute attr, :default => value
    end

    # Used by acts_as_state_machine. Removed in Rails 3.2
    def self.class_inheritable_reader(attr)
      class_attribute attr
    end

    # Used by acts_as_state_machine. Removed in Rails 3.2
    def self.write_inheritable_hash(attr, hash={})
      class_attribute attr, :default => hash
    end

    def self.read_inheritable_attribute(attr)
      send(attr)
    end

  end # class ApplicationRecord
end # module Platform
