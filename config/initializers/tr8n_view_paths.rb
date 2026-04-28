# Rails 3.0 compatibility: manually add tr8n gem view paths
# In Rails 2.3, gems with rails/init.rb are loaded as plugins and view paths are added automatically
# In Rails 3.0, we need to manually add them

if defined?(PlatformGem::Application)
  # Find the tr8n gem path
  tr8n_gem = Gem.loaded_specs.values.find { |spec| spec.name == 'tr8n' }

  if tr8n_gem
    tr8n_views_path = File.join(tr8n_gem.full_gem_path, 'app', 'views')
    if File.directory?(tr8n_views_path)
      # Add tr8n views path to the beginning so it takes precedence
      ActionController::Base.prepend_view_path(tr8n_views_path)
    end
  end
end
