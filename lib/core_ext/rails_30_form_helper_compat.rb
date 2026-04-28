# Rails 3.0 compatibility: form_tag must return SafeBuffer
# In Rails 3.0, form_for expects form_tag to return a SafeBuffer

if defined?(ActionView::Helpers::FormTagHelper)
  module ActionView
    module Helpers
      module FormTagHelper
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
