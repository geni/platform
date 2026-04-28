# Rails 3.0 compatibility patch for asset helpers
# Rails 3.0's asset_tag_helper doesn't handle nil relative_url_root properly

if defined?(ActionView::Helpers::AssetTagHelper)
  module ActionView
    module Helpers
      module AssetTagHelper
        # Patch compute_public_path to handle nil relative_url_root
        alias_method :compute_public_path_without_nil_fix, :compute_public_path

        def compute_public_path(source, dir, ext = nil, include_host = true)
          # Ensure controller.config.relative_url_root is not nil
          if controller.respond_to?(:config) && controller.config.relative_url_root.nil?
            controller.config.relative_url_root = ""
          end
          compute_public_path_without_nil_fix(source, dir, ext, include_host)
        end
      end
    end
  end
end
