require 'test_helper'

module Platform
  class ApplicationUserTest < Platform::TestCase

    test 'for finds the row for this application and user' do
      row = Platform::ApplicationUser.create!(application: app, user: user)

      assert_equal row.id, Platform::ApplicationUser.for(app, user).id
    end

    test 'for is scoped to both the application and the user' do
      Platform::ApplicationUser.create!(application: app, user: user)

      assert_nil Platform::ApplicationUser.for(create_app(name: 'Other'), user)
      assert_nil Platform::ApplicationUser.for(app, create_user('someone else'))
    end

    test 'find_or_create creates the row once' do
      first  = Platform::ApplicationUser.find_or_create(app, user)
      second = Platform::ApplicationUser.find_or_create(app, user)

      assert_equal first.id, second.id
      assert_equal 1, Platform::ApplicationUser.where(application_id: app.id, user_id: user.id).count
    end

    # #touch is what Application#authorize_user and #find_or_create_access_token call to record
    # that a user is using an application, so it has to create the row when there is not one yet.
    test 'touch creates the row when it is missing' do
      assert_nil Platform::ApplicationUser.for(app, user)

      Platform::ApplicationUser.touch(app, user)

      assert_not_nil Platform::ApplicationUser.for(app, user)
    end

    test 'touch bumps updated_at on an existing row without creating a second one' do
      row = Platform::ApplicationUser.create!(application: app, user: user,
                                              updated_at: 3.days.ago)
      was = row.updated_at

      Platform::ApplicationUser.touch(app, user)

      assert_operator row.reload.updated_at, :>, was
      assert_equal 1, Platform::ApplicationUser.where(application_id: app.id, user_id: user.id).count
    end

    test 'for, find_or_create and touch default to the current user' do
      Platform::Config.init(user)

      row = Platform::ApplicationUser.find_or_create(app)
      assert_equal user.id, row.user_id
      assert_equal row.id,  Platform::ApplicationUser.for(app).id

      Platform::ApplicationUser.touch(app)
      assert_equal 1, Platform::ApplicationUser.where(application_id: app.id, user_id: user.id).count
    ensure
      Platform::Config.reset!
    end

    ##########################################################################
    #### The serialized data column
    ##########################################################################

    test 'data round-trips through the YAML coder' do
      row = Platform::ApplicationUser.create!(application: app, user: user,
                                              data: { 'seen' => true, 'count' => 3 })

      assert_equal({ 'seen' => true, 'count' => 3 }, row.reload.data)
    end

    test 'data is nil when nothing was stored' do
      row = Platform::ApplicationUser.create!(application: app, user: user)

      assert_nil row.reload.data
    end

    ##########################################################################
    #### access_token
    ##########################################################################

    # This referred to Platform::AccessToken, which has not existed since the token models moved
    # under the Oauth namespace, so every call raised NameError.
    test 'access_token returns the newest access token for this application and user' do
      app.create_access_token(user, 'basic')
      newest = app.create_access_token(user, 'basic')

      assert_equal newest.id, Platform::ApplicationUser.find_or_create(app, user).access_token.id
    end

    test 'access_token is nil when the user holds none' do
      assert_nil Platform::ApplicationUser.find_or_create(app, user).access_token
    end

    test 'access_token is scoped to this application and user' do
      theirs = create_user('someone else')
      app.create_access_token(theirs, 'basic')
      create_app(name: 'Other').create_access_token(user, 'basic')

      assert_nil Platform::ApplicationUser.find_or_create(app, user).access_token
    end

    # It reads the token table directly rather than filtering on validity, so a revoked or
    # expired token is still what comes back -- the caller has to check #valid_token?.
    test 'access_token does not filter out an invalidated token' do
      token = app.create_access_token(user, 'basic')
      token.invalidate!

      found = Platform::ApplicationUser.find_or_create(app, user).access_token

      assert_equal token.id, found.id
      assert_equal false, found.valid_token?
    end

  end # class ApplicationUserTest
end # module Platform
