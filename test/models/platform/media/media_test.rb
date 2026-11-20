require 'test_helper'

module Platform::Media
  class MediaTest < Platform::TestCase

    ##########################################################################
    #### Paths
    ####
    #### Three derived strings, two of which point at the filesystem and one at the web.  They are
    #### built by joining with "/" rather than File.join, which matters: File.join collapses
    #### repeated separators and these do not.
    ##########################################################################

    test 'local_dir is the configured media path plus the stored location' do
      image = Image.create!(file_location: 'ab/cd/ef/01', file_name: 'icon.png')

      assert_equal "#{Platform::Config.media_path}/ab/cd/ef/01", image.local_dir
    end

    test 'local_path is the local dir plus the stored file name' do
      image = Image.create!(file_location: 'ab/cd/ef/01', file_name: 'icon.png')

      assert_equal "#{Platform::Config.media_path}/ab/cd/ef/01/icon.png", image.local_path
    end

    test 'url is the web media directory, not the filesystem path' do
      image = Image.create!(file_location: 'ab/cd/ef/01', file_name: 'icon.png')

      assert_equal "#{Platform::Config.media_directory}/ab/cd/ef/01/icon.png", image.url
    end

    test 'local_dir and local_path are memoized' do
      image = Image.create!(file_location: 'ab/cd/ef/01', file_name: 'icon.png')
      dir   = image.local_dir
      path  = image.local_path

      image.file_location = 'ff/ff/ff/ff'
      image.file_name     = 'other.png'

      assert_equal dir,  image.local_dir
      assert_equal path, image.local_path
      assert_equal "#{Platform::Config.media_directory}/ff/ff/ff/ff/other.png", image.url,
                   'url is not memoized, so it follows the new attributes'
    end

    ##########################################################################
    #### generate_local_dir
    ####
    #### Spreads files over a four-level tree of 256-way directories, so no one directory
    #### accumulates every upload.  The rjust is what keeps the tree even: without it a small
    #### random number would produce a short hex string and #scan would return fewer than four
    #### pairs -- a two-level path for some files and a four-level one for others.
    ##########################################################################

    test 'generate_local_dir is four hex pairs separated by slashes' do
      assert_match(/\A\h{2}\/\h{2}\/\h{2}\/\h{2}\z/, Media.generate_local_dir)
    end

    test 'generate_local_dir zero-pads a small number to the full four levels' do
      Media.stubs(:rand).returns(0x0a0b)

      assert_equal '00/00/0a/0b', Media.generate_local_dir
    end

    test 'generate_local_dir uses the whole 32-bit range' do
      Media.stubs(:rand).returns(0xffffffff)

      assert_equal 'ff/ff/ff/ff', Media.generate_local_dir
    end

    ##########################################################################
    #### STI
    ##########################################################################

    test 'Image is stored in the shared media table under its own type' do
      image = Image.create!(file_location: 'ab/cd/ef/01', file_name: 'icon.png')

      assert_equal 'platform_media', Image.table_name
      assert_equal 'Platform::Media::Image', image.reload.type
      assert_kind_of Image, Media.find(image.id)
    end

    ##########################################################################
    #### write
    ####
    #### Resizes with Magick::ImageList.  rmagick has always been a declared dependency of this
    #### gem but nothing required it, so Magick was an undefined constant and the method raised
    #### NameError on every call.  It is reachable from Platform::Application#store_icon /
    #### #store_logo and Platform::Scope#store_icon on the branch taken when site media is
    #### disabled -- a host application that supplies its own media class goes through
    #### Platform::Config.create_media instead, which is why this went unnoticed.
    ##########################################################################

    test 'write stores a copy and fills in the location columns' do
      with_tmp_media_path do
        image = Image.create!
        image.write(fixture_image, size: 16)

        assert_equal 'image/png', image.content_type
        assert_match(/\.png\z/, image.file_name)
        assert_match(/\A\h{2}\/\h{2}\/\h{2}\/\h{2}\z/, image.file_location)
        assert File.exist?(image.local_path)
      end
    end

    test 'write resizes to the requested size' do
      with_tmp_media_path do
        image = Image.create!
        image.write(fixture_image, size: 16)

        written = Magick::ImageList.new(image.local_path).first
        assert_equal 16, written.columns
        assert_equal 16, written.rows
      end
    end

    test 'write without a size keeps the original dimensions' do
      with_tmp_media_path do
        image = Image.create!
        image.write(fixture_image)

        written = Magick::ImageList.new(image.local_path).first
        assert_equal 512, written.columns, 'the fixture is 512x512'
      end
    end

    test 'write creates the directory tree it spread the file over' do
      with_tmp_media_path do |root|
        image = Image.create!
        image.write(fixture_image, size: 16)

        assert_equal "#{root}/#{image.file_location}", image.local_dir
        assert File.directory?(image.local_dir)
      end
    end

    test 'write leaves the file world-readable' do
      with_tmp_media_path do
        image = Image.create!
        image.write(fixture_image, size: 16)

        assert_equal '644', format('%o', File::Stat.new(image.local_path).mode & 0o777)
      end
    end

    test 'write persists the record' do
      with_tmp_media_path do
        image = Image.create!
        image.write(fixture_image, size: 16)

        assert_equal image.file_name,     image.reload.file_name
        assert_equal image.file_location, image.file_location
      end
    end

    test 'two writes do not collide' do
      with_tmp_media_path do
        first  = Image.create!.tap { |i| i.write(fixture_image, size: 16) }
        second = Image.create!.tap { |i| i.write(fixture_image, size: 16) }

        assert_not_equal first.local_path, second.local_path
        assert File.exist?(first.local_path)
        assert File.exist?(second.local_path)
      end
    end

  end # class MediaTest
end # module Platform::Media
