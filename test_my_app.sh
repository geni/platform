#!/bin/sh

bundle config --local build.sqlite3 "--enable-system-libraries"
bundle config --local clean true
bundle config --local path vendor/bundle
bundle config --local without vscode

# The bundler version can change between branches
rm -f Gemfile.lock

bundle install

rm -f db/test.sqlite3
bundle exec rake db:migrate test
