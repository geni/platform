# Rails 3.2 removed write_inheritable_attribute, read_inheritable_attribute,
# class_inheritable_reader, and class_inheritable_writer
# Some gems (like acts_as_state_machine 2.2.0) still use these methods
# This shim provides compatibility using class instance variables and accessors

if defined?(ActiveRecord::Base) && !ActiveRecord::Base.respond_to?(:write_inheritable_attribute)
  class Class
    def write_inheritable_attribute(key, value)
      ivar = "@#{key}"

      # Set the class instance variable
      instance_variable_set(ivar, value)

      # Define getter if it doesn't exist
      unless respond_to?(key)
        define_singleton_method(key) do
          instance_variable_get(ivar)
        end
      end

      # Define setter if it doesn't exist
      unless respond_to?("#{key}=")
        define_singleton_method("#{key}=") do |val|
          instance_variable_set(ivar, val)
        end
      end
    end

    def read_inheritable_attribute(key)
      ivar = "@#{key}"
      instance_variable_get(ivar) if instance_variable_defined?(ivar)
    end

    def class_inheritable_reader(*syms)
      syms.each do |sym|
        ivar = "@#{sym}"
        define_singleton_method(sym) do
          instance_variable_get(ivar)
        end
      end
    end

    def class_inheritable_writer(*syms)
      syms.each do |sym|
        ivar = "@#{sym}"
        define_singleton_method("#{sym}=") do |val|
          instance_variable_set(ivar, val)
        end
      end
    end

    def class_inheritable_accessor(*syms)
      class_inheritable_reader(*syms)
      class_inheritable_writer(*syms)
    end

    def write_inheritable_hash(key, hash)
      ivar = "@#{key}"
      # Merge with existing hash if it exists, otherwise create new
      existing = instance_variable_get(ivar) if instance_variable_defined?(ivar)
      merged = existing ? existing.merge(hash) : hash
      instance_variable_set(ivar, merged)

      # Define getter if it doesn't exist
      unless respond_to?(key)
        define_singleton_method(key) do
          instance_variable_get(ivar)
        end
      end
    end
  end
end
