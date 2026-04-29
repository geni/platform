# Add your own tasks in files placed in lib/tasks ending in .rake,
# for example lib/tasks/capistrano.rake, and they will automatically be available to Rake.

require(File.join(File.dirname(__FILE__), 'config', 'boot'))

require 'rake'
require 'rake/testtask'

# Rails 2.3 used tasks/rails, Rails 3.0+ uses bundler and environment
begin
  require 'tasks/rails'
rescue LoadError
  # Rails 3.0+ - load environment which sets everything up via bundler
  require File.expand_path('../config/environment', __FILE__)

  # Load ActiveRecord for Rails 3.0+
  require 'active_record'

  # Database tasks for Rails 3.0+
  namespace :db do
    task :migrate do
      # Ensure clean database
      db_file = File.join(File.dirname(__FILE__), 'db', 'test.sqlite3')
      File.delete(db_file) if File.exist?(db_file)

      ActiveRecord::Base.establish_connection(
        adapter: 'sqlite3',
        database: 'db/test.sqlite3'
      )

      # Load schema if it exists
      schema_file = File.join(File.dirname(__FILE__), 'db', 'schema.rb')
      load(schema_file) if File.exist?(schema_file)
    end
  end

  # Test task for Rails 3.0+
  Rake::TestTask.new(:test => 'db:migrate') do |t|
    t.libs << 'lib'
    t.libs << 'test'
    t.pattern = 'test/**/*_test.rb'
    t.verbose = true
  end

  task default: :test
end
