#!/bin/sh

set -e

# Pick a bundler that supports the Ruby we are about to run.
#
# `gem install bundler --user-install` puts the gem in ~/.local/share/gem/ruby/gems, a path with
# no Ruby version in it, so it is shared by every Ruby on the machine.  A bundler installed while
# a Ruby 3.x was current is therefore visible here too -- and the `bundle` binstub activates the
# *newest* installed gem without consulting its required_ruby_version.  On this branch that means
# bundler 2.7.2 (which declares `required_ruby_version >= 3.2.0`) is chosen for Ruby 2.7.8 and
# dies before it reads the Gemfile:
#
#   uninitialized constant Gem::Resolver::APISet::GemParser (NameError)
#     from .../bundler-2.7.2/lib/bundler/rubygems_ext.rb:465
#
# A lockfile would have steered around it -- bundler re-execs the version named in BUNDLED WITH
# when that version is installed -- but the `rm` below deletes the lockfile before `bundle
# install` runs, so there is nothing left to steer with.  Hence choosing explicitly, newest
# first, rather than pinning a version that would go stale the next time the Ruby moves.
BUNDLER_VERSION=`ruby -rrubygems -e '
  usable = Gem::Specification.find_all_by_name("bundler").select { |s|
    s.required_ruby_version.satisfied_by?(Gem::Version.new(RUBY_VERSION))
  }
  if usable.empty?
    all = Gem::Specification.find_all_by_name("bundler").map { |s| s.version.to_s }.sort.join(", ")
    warn "No installed bundler supports ruby #{RUBY_VERSION} (installed: #{all})."
    warn "Install one:  gem install bundler -v 2.4.22 --user-install"
    exit 1
  end
  puts usable.max_by(&:version).version
'`
export BUNDLER_VERSION

echo "using bundler $BUNDLER_VERSION on ruby `ruby -e 'print RUBY_VERSION'`"

bundle config --local build.sqlite3 "--enable-system-libraries"
bundle config --local clean true
bundle config --local path vendor/bundle
bundle config --local without vscode

# The bundler version can change between branches
rm -f Gemfile.lock

bundle install

rm -f db/test.sqlite3
bundle exec rake db:migrate test
