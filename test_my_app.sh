#!/bin/sh

unset RBENV_VERSION
export RBENV_ROOT=/opt/rbenv
export PATH=${RBENV_ROOT}/shims:${PATH}:${RBENV_ROOT}/bin

git gc

bundle config --local build.pg "--with-pg-config=/usr/pgsql-10/bin/pg_config"
bundle config --local build.sqlite3 "--enable-system-libraries"
bundle config --local clean true
bundle config --local path vendor/bundle
bundle config --local without vscode

rm -f Gemfile.lock
bundle install

rm -f db/test.sqlite3
bundle exec rake db:migrate test
