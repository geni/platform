$:.push File.expand_path("../lib", __FILE__)

# Describe your gem and declare its dependencies:
Gem::Specification.new do |s|
  s.name        = "platform"
  s.version     = IO.read('VERSION')
  s.authors     = ["Michael Berkovich", "Scott Steadman"]
  s.email       = ["theiceberk@gmail.com", "scott.steadman@geni.com"]
  s.homepage    = "https://github.com/geni/platform"
  s.summary     = "Application Developer platform for extanding Rails applications by 3rd party developers."
  s.description = "This gem provides all necessary tools to make a Rails application into a platform with third party applications."
  s.require_paths = ['lib']
end
