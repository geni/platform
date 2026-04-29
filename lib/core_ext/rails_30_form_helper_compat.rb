# Rails 3.0-3.1 compatibility: form_tag must return SafeBuffer
# In Rails 3.0-3.1, form_for expects form_tag to return a SafeBuffer
# This can fail in test mode where the output buffer is a String

if defined?(ActionView::Helpers::FormTagHelper) && defined?(Rails::VERSION) && Rails::VERSION::MAJOR == 3 && [0, 1].include?(Rails::VERSION::MINOR)
  module ActionView
    module Helpers
      module FormTagHelper
        if method_defined?(:form_tag)
          alias_method :form_tag_without_safe_buffer, :form_tag

          def form_tag(url_for_options = {}, options = {}, &block)
            output = form_tag_without_safe_buffer(url_for_options, options, &block)
            # Ensure output is a SafeBuffer
            output.is_a?(ActiveSupport::SafeBuffer) ? output : ActiveSupport::SafeBuffer.new(output)
          end
        end
      end
    end
  end
end
