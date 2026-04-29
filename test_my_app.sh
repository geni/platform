#!/bin/sh

# Show which tests are being run and their results
export TEST_OPTS="--verbose --no-show-detail-immediately --stop-on-failure"

bundle config --local build.sqlite3 "--enable-system-libraries"
bundle config --local clean true
bundle config --local path vendor/bundle
bundle config --local without vscode

# clean and reinstall unless --no-clean is specified
if [[ "$*" != *--no-clean* ]]; then
  git gc

  rm -rf Gemfile.lock vendor/bundle
  bundle _1.17.3_ install
fi

# This is a gem/engine, not a full Rails app, so we just run the tests directly
bundle _1.17.3_ exec rake test
