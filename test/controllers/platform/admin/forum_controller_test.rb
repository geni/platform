require 'test_helper'

# The admin's view of both forums.  Both actions are a will_filter list and nothing else, so what
# they are really exercising is that the filter classes resolve -- they name their model classes
# and join columns as strings, which nothing checks until the screen is opened.
class Platform::Admin::ForumControllerTest < Platform::ControllerTestCase

  test 'index requires an admin' do
    login_as user
    get :index
    assert_redirected_to Platform::Config.default_url
  end

  test 'index lists every topic' do
    site_wide = Platform::ForumTopic.create!(user: user, topic: 'Site wide')
    about_app = Platform::ForumTopic.create!(user: user, topic: 'About the app', subject: app)
    login_as admin_user

    get :index
    assert_response :success
    assert_includes assigned(:topics).results.to_a, site_wide
    assert_includes assigned(:topics).results.to_a, about_app
  end

  test 'messages requires an admin' do
    login_as user
    get :messages
    assert_redirected_to Platform::Config.default_url
  end

  test 'messages lists every message' do
    topic = Platform::ForumTopic.create!(user: user, topic: 'A topic', subject: app)
    posted = Platform::ForumMessage.create!(topic: topic, user: user, message: 'A message')
    login_as admin_user

    get :messages
    assert_response :success
    assert_includes assigned(:messages).results.to_a, posted
  end

end # class Platform::Admin::ForumControllerTest
