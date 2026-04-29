# Rails 3.0 compatibility patch for asset helpers
# Rails 3.0's asset_tag_helper doesn't handle nil relative_url_root properly
# Rails 3.1+ uses the asset pipeline, so this patch is not needed

if defined?(ActionView::Helpers::AssetTagHelper)
  # Only apply for Rails 3.0
  should_patch = true
  if defined?(Rails::VERSION)
    should_patch = (Rails::VERSION::MAJOR == 3 && Rails::VERSION::MINOR == 0)
  end

  if should_patch
    module ActionView
      module Helpers
        module AssetTagHelper
          # Patch compute_public_path to handle nil relative_url_root
          if method_defined?(:compute_public_path) && !method_defined?(:compute_public_path_without_nil_fix)
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
  end
end
