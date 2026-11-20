require 'test_helper'

module Platform::Developer
  class DeveloperTest < Platform::TestCase

    test 'find_or_create creates the developer record once per user' do
      first  = Developer.find_or_create(user)
      second = Developer.find_or_create(user)

      assert_equal first.id, second.id
      assert_equal 1, Developer.where(user_id: user.id).count
    end

    test 'find_or_create copies the name and email off the user' do
      someone = ::User.create!(name: 'Ada Lovelace', email: 'ada@example.com')

      dev = Developer.find_or_create(someone)

      assert_equal 'Ada Lovelace',    dev.name
      assert_equal 'ada@example.com', dev.email
      assert_equal someone.id,        dev.user_id
    end

    ##########################################################################
    #### for
    ####
    #### What the host application calls on every request through
    #### Platform::Config.init, so its nil cases are the common path rather than the exception:
    #### most visitors are not developers, and some are not logged in at all.
    ##########################################################################

    test 'for finds the developer record belonging to a user' do
      dev = Developer.find_or_create(user)

      assert_equal dev.id, Developer.for(user).id
    end

    test 'for returns nil for a user with no developer record' do
      assert_nil Developer.for(create_user('not a developer'))
    end

    test 'for returns nil for nil, and for an unsaved user' do
      assert_nil Developer.for(nil)
      assert_nil Developer.for(::User.new(name: 'unsaved'))
    end

    # ::User#guest? in the dummy application is a name check, which is what makes this testable
    # here; in the host application it is a real anonymous-session flag.  A guest must never
    # resolve to a developer even if a row happens to exist for that user id.
    test 'for returns nil for a guest' do
      guest = create_user('Guest')
      Developer.find_or_create(guest)

      assert_equal true, Platform::Config.guest_user?(guest)
      assert_nil Developer.for(guest)
    end

    ##########################################################################
    #### ensure_name
    ####
    #### name is NOT NULL, and #find_or_create_by (which the test helper and the developer
    #### screens both use) passes only the user -- so without this callback creating a developer
    #### that way would be a NOT NULL violation.
    ##########################################################################

    test 'the name defaults to the user name on create' do
      someone = create_user('Grace Hopper')

      dev = Developer.create!(user: someone)

      assert_equal 'Grace Hopper', dev.name
    end

    test 'an explicit name is kept' do
      dev = Developer.create!(user: create_user('Grace Hopper'), name: 'Trading As Ltd')

      assert_equal 'Trading As Ltd', dev.name
    end

    # The callback is on: :create, so an update that blanks the name is not rescued by it.
    test 'the name is required' do
      assert_raise ActiveRecord::NotNullViolation do
        Developer.find_or_create(user).update!(name: nil)
      end
    end

    ##########################################################################
    #### app_options
    ##########################################################################

    test 'app_options pairs each application name with its id' do
      dev   = Developer.find_or_create(user)
      one   = create_app(name: 'One', developer: dev)
      two   = create_app(name: 'Two', developer: dev)

      assert_equal [['One', one.id], ['Two', two.id]], dev.app_options.sort_by(&:first)
    end

    test 'app_options is empty for a developer with no applications' do
      assert_equal [], Developer.find_or_create(user).app_options
    end

    test 'app_options only lists this developer applications' do
      mine   = Developer.find_or_create(user)
      theirs = Developer.find_or_create(create_user('other developer'))
      create_app(name: 'Theirs', developer: theirs)

      assert_equal [], mine.app_options
    end

    ##########################################################################
    #### Associations
    ##########################################################################

    test 'a developer belongs to a user and has many applications' do
      dev = Developer.find_or_create(user)
      one = create_app(name: 'One', developer: dev)

      assert_equal user.id, dev.reload.user.id
      assert_equal [one.id], dev.applications.map(&:id)
    end

  end # class DeveloperTest
end # module Platform::Developer
