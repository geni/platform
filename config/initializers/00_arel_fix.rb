# Fix for Arel 3.0.3 "Cannot visit Integer" error with validates_uniqueness_of
# This patches Arel to properly handle integer values in WHERE clauses
module Arel
  module Visitors
    class ToSql
      private

      def visit_Integer(o)
        quote(o).to_s
      end
    end
  end
end
