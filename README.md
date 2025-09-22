# Platform Engine

## Installation

Add the following lines to the specified files:

```ruby
# Gemfile
gem 'platform', :git => 'https://github.com/geni/platform.git', :branch => 'rails-8.0.x'

# config/routes.rb
Rails.application.routes.draw do
  # Update config/initialiers/platform.rb if the mount point changes.
  mount Platform::Engine => '/foo'
  ...
end

# app/views/layouts/application.html.erb
...
<%= platform_scripts_tag %>
...
```

### Sprockets changes

If you're using the sprockets asset pipeline add the following line to app/assets/config/manifest.js.

```javascript
//= link platform
```

## Development

## Changing javascript files

If you change javascript files, run the following commands:

```sh
bundle exec rails app:platform:bundle_assets
```

This will bundle the javascript changes you made into files specified
in app/assets/javascripts/platform/config.yml. The generated files will be
in app/assets/javascripts/platform.

## Annotating models

```sh
bundle exec annotaterb models -p before
``

## Testing

### Running Automated Tests

```sh
# run all tests and generate coverage report in coverage subdir
bundle exec rails db:create db:migrate
bundle exec rails test
```

### Manual Integration Testing

```sh
# populate dummy app database
bundle exec rails db:create
bundle exec rails db:seed

# Spin up the server
bundle exec rails server -b 0.0.0.0
```

## Upgrading

```sh
git checkout -b rails-x.y.z
gem install rails-x.y.z

# generate new engine subdir.
rails plugin new platform --rc=.railsrc

# copy files over and test.
```

This will create a new engine in the platform subdirectory.
You should copy the files over, then make sure the tests pass.

## References

[Rails Engines](https://guides.rubyonrails.org/engines.html)

## License
The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).
