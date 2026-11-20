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

# == Schema Information
#
# Table name: platform_media
#
#  id            :integer          not null, primary key
#  content_type  :string
#  file_location :string
#  file_name     :string
#  type          :string
#  created_at    :datetime
#  updated_at    :datetime
#
module Platform
  module Media
    class Media < ApplicationRecord

      def local_dir
        @local_dir ||= [Platform::Config.media_path, file_location].join("/")
      end

      def local_path
        @local_path ||= [local_dir, file_name].join("/")
      end

      def url
        [Platform::Config.media_directory, file_location, file_name].join("/")
      end

      def write(file, opts = {})
        # rmagick has been a declared dependency of this gem since the beginning (see
        # platform.gemspec) but nothing ever required it, so Magick below was an undefined
        # constant and this method raised NameError on every call.
        #
        # Required here rather than at boot because it loads a large native library, this is the
        # only thing in the gem that touches it, and it runs only on the fallback image path -- a
        # host application with its own site media class never reaches it, but it does autoload
        # this class, since Platform::Media::Image is the default for Config.site_media_class.
        require 'rmagick'

        self.content_type = 'image/png'
        self.file_location = self.class.generate_local_dir
        self.file_name = "#{Platform::RandomPasswordGenerator.random_password}.png"

        FileUtils.mkdir_p(local_dir) unless File.exist?(local_dir)

        image = Magick::ImageList.new(file.path)
        image = image.resize(opts[:size], opts[:size]) if opts[:size]
        image.write(local_path)
        FileUtils.chmod(0644, local_path)

        save
      end

      def self.generate_local_dir
        rand(2 ** 32).to_s(16).rjust(8, "0").scan(/.{2}/).join("/")
      end

    end # class Media
  end # module Media
end # module Platform
