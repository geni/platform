#!/bin/sh

# Usage: time ./claude_test.sh | tee claude.out

# turn on debugging
#set -x

# stop if any command fails
set -e
set -o pipefail

# This used to loop over 'current' and 'next', installing each side of a next_rails dual boot and
# running the suite twice -- the 'next' side through the `next` binary with bundler 1.17.3, the
# 'current' side on Rails 2.3.  The dual boot is gone: this branch is Rails 3.0 and nothing else,
# so there is one side left and no `next` binary to call.
#
# test_my_app.sh is the script that picks a bundler this Gemfile can actually resolve with --
# Rails 3.0.20 requires `bundler (~> 1.0)` -- so the install is delegated there rather than
# duplicated.  This script adds what it does not do: a clean vendor/bundle, and verbose
# stop-on-failure test output.

# Show which tests are being run and their results
#export TEST_OPTS="--verbose --no-show-detail-immediately"
export TEST_OPTS="--verbose --no-show-detail-immediately --stop-on-failure"

# In case claude made changes to gems
rm -rf vendor/bundle

rm -f log/test.log

./test_my_app.sh
