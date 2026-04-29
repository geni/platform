# Arel 3.x (Rails 3.2) compatibility patch
# Arel 3.x ToSql visitor doesn't have a visit_Integer method, causing errors
# when WHERE clauses contain raw integers
# This adds the missing visitor method

if defined?(Arel::VERSION) && Arel::VERSION =~ /^3\./
  module Arel
    module Visitors
      class ToSql
        # Add visit_Integer method for handling raw integer values in WHERE clauses
        unless method_defined?(:visit_Integer)
          def visit_Integer(o)
            o.to_s
          end
        end
      end
    end
  end
end
