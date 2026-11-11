#--
# Copyright (c) 2011 Michael Berkovich
#
# Permission is hereby granted, free of charge, to any person obtaining
# a copy of this software and associated documentation files (the
# "Software"), to deal in the Software without restriction, including
# without limitation the rights to use, copy, modify, merge, publish,
# distribute, sublicense, and/or sell copies of the Software, and to
# permit persons to whom the Software is furnished to do so, subject to
# the following conditions:
#
# The above copyright notice and this permission notice shall be
# included in all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
# EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
# MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
# NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE
# LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION
# OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION
# WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
#++

require 'logger'
require 'fileutils'

class Platform::Logger < Logger

  # This used to write to tr8n's logfile, which is not as odd as it looks: the body of this
  # method was copied from tr8n's logger, the class name was changed, and the configuration
  # references were not.  Four things followed from that.
  #
  #   * It read Tr8n::Config.log_path, so every line this gem logged went to log/tr8n.log --
  #     a translation log -- while platform's own `logger:` block in config/platform/config.yml
  #     (log_path: log/platform.log) was dead configuration and Platform::Config.logger had no
  #     callers anywhere.
  #   * It read Tr8n::Config.enable_logger?, so platform's own enabled flag did nothing either.
  #   * It instantiated Tr8n::Logger rather than itself, which made #format_message below
  #     unreachable -- platform's lines were formatted by tr8n's logger.
  #   * It interpolated RAILS_ROOT, which Rails 3 removed.  That has never raised here only
  #     because the host application defines RAILS_ROOT in config/boot.rb for 2.3
  #     compatibility; any other host on Rails 3 or later would have hit NameError on its first
  #     log line, and on this gem's own rails-8.0.x branch it was one config change away from
  #     doing so.
  #
  # It also meant this gem could not log at all unless tr8n was loaded and configured, which is
  # a strange thing for an OAuth provider to require.
  def self.logger
    @logger ||= build_logger
  end

  # Separated so the rescue cannot swallow a failure in the memoisation itself, and so a test
  # can reset @logger and rebuild.
  def self.build_logger
    settings = Platform::Config.logger || {}
    return Rails.logger unless settings[:enabled]

    path = settings[:log_path].to_s
    path = 'log/platform.log' if path.empty?
    path = File.join(Rails.root.to_s, path) unless path.start_with?('/')

    FileUtils.mkdir_p(File.dirname(path))

    logfile = File.open(path, 'a')
    logfile.sync = true
    new(logfile)
  rescue StandardError => ex
    # A logger must never be the thing that breaks a request.  This class carries the OAuth
    # staged-enforcement lines, which run on the token endpoint on every exchange -- an
    # unwritable log directory should cost a log line, not a 500.
    fallback = (Rails.logger rescue nil)
    if fallback
      fallback.error("Platform::Logger could not open its logfile " \
                     "(#{ex.class}: #{ex.message}); falling back to the Rails logger")
    end
    fallback || Logger.new($stderr)
  end

  def self.reset!
    @logger = nil
  end

  def format_message(severity, timestamp, progname, msg)
    "#{timestamp.to_formatted_s(:db)}: #{msg}\n"
  end

  def self.debug(msg)
    logger.debug(msg)
  end

  def self.info(msg)
    logger.info(msg)
  end

  def self.error(msg)
    logger.error(msg)
  end

  def self.fatal(msg)
    logger.fatal(msg)
  end
end
