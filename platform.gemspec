require_relative "lib/platform/version"

Gem::Specification.new do |spec|
  spec.name        = "platform"
  spec.version     = Platform::VERSION
  spec.authors     = ["Michael Berkovich", "Scott Steadman"]
  spec.email       = ["theiceberk@gmail.com", "scott.steadman@geni.com"]
  spec.homepage    = "https://github.com/geni/platform"
  spec.summary     = "Application Developer platform for extanding Rails applications by 3rd party developers."
  spec.description = "This gem provides all necessary tools to make a Rails application into a platform with third party applications."
  spec.license     = "MIT"

  # Prevent pushing this gem to RubyGems.org. To allow pushes either set the "allowed_push_host"
  # to allow pushing to a single host or delete this section to allow pushing to any host.
  spec.metadata["allowed_push_host"] = "none"

  spec.files = Dir.chdir(File.expand_path(__dir__)) do
    Dir["{app,config,db,lib}/**/*", "MIT-LICENSE", "Rakefile", "README.md"]
  end

  spec.add_dependency 'acts_as_state_machine'
  spec.add_dependency 'acts_as_tree'
  spec.add_dependency "rails", ">= 8.0.1"
  spec.add_dependency 'rmagick'
  spec.add_dependency 'sprockets-rails'
  spec.add_dependency 'tr8n'
  spec.add_dependency 'will_filter'
  spec.add_dependency 'will_paginate'
end

