#!/bin/sh

set -e

# Find a bundler that can actually install this branch, and use it for everything after.
#
# Two separate things rule candidates out, which is why this is a loop and not a single answer.
#
# 1. The Ruby.  `gem install bundler --user-install` installs into ~/.local/share/gem/ruby/gems,
#    a path with no Ruby version in it, so it is shared by every Ruby on the machine: a bundler
#    installed while a Ruby 3.x was current is visible to Ruby 2.7 too.  The `bundle` binstub
#    activates the *newest* installed gem and never consults its required_ruby_version, so Ruby
#    2.7.8 gets handed bundler 2.7.2 (`required_ruby_version >= 3.2.0`) and dies before it has
#    read the Gemfile:
#
#      uninitialized constant Gem::Resolver::APISet::GemParser (NameError)
#        from .../bundler-2.7.2/lib/bundler/rubygems_ext.rb:465
#
#    A lockfile would have steered around that, since bundler re-execs the version in BUNDLED
#    WITH -- but the `rm` below deletes the lockfile before `bundle install` runs, so there is
#    nothing left to steer with.  Hence choosing explicitly.
#
# 2. The Gemfile.  Being compatible with the Ruby is not sufficient: rails 3.0.20 requires
#    `bundler (~> 1.0)`, so on a branch pinned to it, bundler 2.x loads fine and then refuses to
#    resolve --
#
#      Bundler could not find compatible versions for gem "bundler":
#        rails (= 3.0.20) was resolved to 3.0.20, which depends on bundler (~> 1.0)
#
#    which is why rails-3.2.x pins `bundle _1.17.3_` by hand.  Only bundler itself knows whether
#    it can resolve a given Gemfile, so the honest test is to try.
#
# Newest first, so a branch that can use a modern bundler does, and an old one falls back without
# anybody having to hardcode which is which.  That is what "the bundler version can change
# between branches" below has always meant; it just was not enforced.
# stubs_for, not find_all_by_name: the latter is narrowed by the working directory.  Run from
# this directory it reports only bundler 1.17.3; run from /tmp it reports all four that are
# installed.  Depending on that would mean the candidate list changes with where the script is
# invoked from, and silently.  to_spec because a stub does not carry required_ruby_version.
CANDIDATES=`ruby -rrubygems -e '
  specs  = Gem::Specification.stubs_for("bundler").map(&:to_spec).compact
  usable = specs.select { |s|
    s.required_ruby_version.satisfied_by?(Gem::Version.new(RUBY_VERSION))
  }
  if usable.empty?
    all = specs.map { |s| s.version.to_s }.sort.join(", ")
    warn "No installed bundler supports ruby #{RUBY_VERSION} (installed: #{all})."
    warn "Install one:  gem install bundler -v 1.17.3 --user-install"
    exit 1
  end
  puts usable.map(&:version).sort.reverse.join(" ")
'`

echo "ruby `ruby -e 'print RUBY_VERSION'`; bundler candidates, newest first: $CANDIDATES"

BUNDLER_VERSION=""
for v in $CANDIDATES; do
  echo "--- trying bundler $v"

  # Written by the same bundler that is about to install, because bundler 1 and bundler 2 do not
  # agree on every key in .bundle/config.
  bundle _${v}_ config --local build.sqlite3 "--enable-system-libraries"
  bundle _${v}_ config --local clean true
  bundle _${v}_ config --local path vendor/bundle
  bundle _${v}_ config --local without vscode

  # The bundler version can change between branches
  rm -f Gemfile.lock

  if bundle _${v}_ install; then
    BUNDLER_VERSION="$v"
    break
  fi

  echo "--- bundler $v could not install this Gemfile; falling back to an older one"
done

if [ -z "$BUNDLER_VERSION" ]; then
  echo "No installed bundler could install this Gemfile.  Tried: $CANDIDATES" >&2
  exit 1
fi

export BUNDLER_VERSION
echo "using bundler $BUNDLER_VERSION on ruby `ruby -e 'print RUBY_VERSION'`"

rm -f db/test.sqlite3
bundle exec rake db:migrate test
