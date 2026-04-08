#!/bin/sh

#bundle config --local build.pg "--with-pg-config=/usr/pgsql-15/bin/pg_config"
bundle config --local clean true
bundle config --local path vendor/bundle
bundle config --local without vscode

rm -rf Gemfile.lock vendor/bundle
bundle install

bundle exec rails db:create db:migrate

bundle exec rails test
