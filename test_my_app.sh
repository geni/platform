#!/bin/sh

bundle config --local clean true
bundle config --local path vendor/bundle
bundle config --local without vscode

# The bundler version can change between branches
rm -rf Gemfile.lock vendor/bundle
bundle install

bundle exec rails db:create db:migrate

bundle exec rails test
