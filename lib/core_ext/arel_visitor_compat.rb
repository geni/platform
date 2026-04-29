# Arel 2.x and 3.x (Rails 3.0-3.2) compatibility patch
# Arel 2.0-2.2's ToSql visitor doesn't have a visit_Integer method, causing errors
# when LIMIT/OFFSET clauses contain raw integers
# Arel 3.x also needs this for WHERE clause conditions
# This adds the missing visitor method

if defined?(Arel::VERSION) && Arel::VERSION =~ /^[23]\./
  module Arel
    module Visitors
      class ToSql
        # Add visit_Integer method for handling raw integer values in LIMIT/OFFSET and WHERE clauses
        unless method_defined?(:visit_Integer)
          def visit_Integer(o)
            o.to_s
          end
        end
      end
    end
  end
end
