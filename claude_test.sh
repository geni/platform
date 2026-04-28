#!/bin/sh

# Usage: time ./claude_test.sh | tee claude.out

# turn on debugging
#set -x

# stop if any command fails
set -e
set -o pipefail

bundle config --local build.sqlite3 "--enable-system-libraries"
bundle config --local clean true
bundle config --local path vendor/bundle
bundle config --local without vscode


# Show which tests are being run and their results
#export TEST_OPTS="--verbose --no-show-detail-immediately"
export TEST_OPTS="--verbose --no-show-detail-immediately --stop-on-failure"

# In case claude made changes to gems
rm -rf vendor/bundle
rm -f Gemfile.lock Gemfile.next.lock

# Run tests in order: Rails 3.0 first, then Rails 3.1
for run in 'current' 'next'
do
  echo "*** Testing ${run}..." && sleep 2

  rm -f log/test.log

  # Reinstall gems before each test run to ensure correct versions
  if [ "$run" = "next" ]; then
#    export BUNDLE_GEMFILE=Gemfile.next
    next bundle _1.17.3_ install
    bx="next bundle _1.17.3_ exec"
  else
#    unset BUNDLE_GEMFILE
    bundle install
    bx="bundle exec"
  fi

  # Undike for rails 6.1+
  #$bx rails zeitwerk:check

  rm -f db/test.sqlite3
  $bx rake db:migrate test
done
