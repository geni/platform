require 'test_helper'

module Platform
  class RatingTest < Platform::TestCase

    test 'for finds the rating this user left on this application' do
      mine = Platform::Rating.create!(object: app, user: user, value: 4)
      Platform::Rating.create!(object: app, user: create_user('someone else'), value: 1)

      assert_equal mine.id, Platform::Rating.for(app, user).id
    end

    test 'for is scoped to the application as well as the user' do
      Platform::Rating.create!(object: app, user: user, value: 4)

      assert_nil Platform::Rating.for(create_app(name: 'Other'), user)
    end

    test 'find_or_create returns the existing rating rather than a second one' do
      first  = Platform::Rating.find_or_create(app, user)
      second = Platform::Rating.find_or_create(app, user)

      assert_equal first.id, second.id
      assert_equal 1, Platform::Rating.where(object_type: 'Platform::Application',
                                             object_id: app.id,
                                             user_id: user.id).count
    end

    test 'find_or_create records the polymorphic object' do
      rating = Platform::Rating.find_or_create(app, user)

      assert_equal 'Platform::Application', rating.object_type
      assert_equal app.id, rating.object_id
      assert_equal app, rating.object
    end

    # Both finders default their user argument to Platform::Config.current_user, which is
    # thread-local state the host application sets per request.
    test 'for and find_or_create default to the current user' do
      Platform::Config.init(user)

      rating = Platform::Rating.find_or_create(app)
      assert_equal user.id, rating.user_id
      assert_equal rating.id, Platform::Rating.for(app).id
    ensure
      Platform::Config.reset!
    end

    ##########################################################################
    #### toHTML
    ##########################################################################

    test 'toHTML escapes the comment and turns newlines into breaks' do
      rating = Platform::Rating.new(comment: "<b>nice</b> & cheap\napp")

      assert_equal '&lt;b&gt;nice&lt;/b&gt; &amp; cheap<br>app', rating.toHTML
    end

    test 'toHTML is blank when there is no comment' do
      assert_equal '', Platform::Rating.new.toHTML
    end

  end # class RatingTest
end # module Platform
