#Rails.autoloaders.each(&:log!)

[
  Platform::Engine.root.join('lib/generators/'),
  Platform::Engine.root.join('lib/platform/version.rb'),
  Platform::Engine.root.join('lib/tasks/'),
].each do |path|
  Rails.autoloaders.main.ignore(path)
end