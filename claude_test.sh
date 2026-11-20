#!/bin/sh

# Usage: time ./claude_test.sh | tee claude.out

# turn on debugging
#set -x

# stop if any command fails
set -e
set -o pipefail

# This used to loop over 'current' and 'next', installing each side of a next_rails dual boot and
# running the suite twice -- the 'next' side with BUNDLE_GEMFILE=Gemfile.next on Rails 3.1, the
# 'current' side on Rails 3.0.  The dual boot is gone: this branch is Rails 3.1 and nothing else.
#
# test_my_app.sh is the script that picks a bundler this Gemfile can actually resolve with, so the
# install is delegated there rather than duplicated.  This script adds what it does not do: a clean
# vendor/bundle, and stop-on-failure test output.

# Note: --verbose causes test-unit 3.5.7/3.6.x to crash with local_name error on nested test suites
#export TEST_OPTS="--verbose --no-show-detail-immediately"
export TEST_OPTS="--no-show-detail-immediately --stop-on-failure"

# In case claude made changes to gems
rm -rf vendor/bundle

rm -f log/test.log

./test_my_app.sh
