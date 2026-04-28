# Arel 2.0 (Rails 3.0) compatibility patch
# Arel 2.0's ToSql visitor doesn't have a visit_Integer method, causing errors
# when LIMIT/OFFSET clauses contain raw integers
# This adds the missing visitor method

if defined?(Arel::VERSION) && Arel::VERSION =~ /^2\.0\./
  module Arel
    module Visitors
      class ToSql
        # Add visit_Integer method for handling raw integer values in LIMIT/OFFSET
        def visit_Integer(o)
          o.to_s
        end
      end
    end
  end
end
