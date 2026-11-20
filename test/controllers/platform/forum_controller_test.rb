require 'test_helper'

# The per-application discussions, as opposed to the site-wide developer forum in
# Platform::Developer::ForumController.  Every action here ends up back on the application's own
# page, or wherever the request came from.
class Platform::ForumControllerTest < Platform::ControllerTestCase

  test 'new_message requires login' do
    post :new_message, params: {app_id: app.id, topic: 'A topic', message: 'Hello',
                                authenticity_token: form_authenticity_token}
    assert_redirected_to Platform::Config.default_url
  end

  test 'new_message starts a discussion on the application' do
    login_as user

    assert_difference ['Platform::ForumTopic.count', 'Platform::ForumMessage.count'] do
      post :new_message, params: {app_id: app.id, topic: 'A topic', message: 'Hello',
                                  authenticity_token: form_authenticity_token}
    end

    started = Platform::ForumTopic.order('id desc').first
    assert_equal app, started.subject
    assert_equal user, started.user
    assert_equal 'A topic', started.topic
    assert_equal 'Hello', started.last_post.message

    assert_redirected_to controller: '/platform/apps', action: :view, id: app.id,
                         sec: 'Discussions', topic_id: started.id, last_page: true
  end

  test 'new_message adds a message to an existing discussion' do
    login_as user
    discussion = create_topic

    assert_no_difference 'Platform::ForumTopic.count' do
      assert_difference 'Platform::ForumMessage.count' do
        post :new_message, params: {app_id: app.id, topic_id: discussion.id, message: 'A reply',
                                    authenticity_token: form_authenticity_token}
      end
    end

    assert_equal 'A reply', discussion.last_post.message
    assert_redirected_to controller: '/platform/apps', action: :view, id: app.id,
                         sec: 'Discussions', topic_id: discussion.id, last_page: true
  end

  # A GET posts nothing.  The redirect still has to work, which is why #new_message builds it with
  # &. -- there is no topic on this path.
  test 'new_message does not post anything over GET' do
    login_as user

    assert_no_difference 'Platform::ForumMessage.count' do
      get :new_message, params: {app_id: app.id, topic: 'A topic', message: 'Hello'}
    end

    assert_redirected_to controller: '/platform/apps', action: :view, id: app.id,
                         sec: 'Discussions', last_page: true
  end

  test 'new_message on an application that does not exist' do
    login_as user

    assert_raises ActiveRecord::RecordNotFound do
      post :new_message, params: {app_id: 0, message: 'Hello', authenticity_token: form_authenticity_token}
    end
  end

  ##########################################################################
  #### delete_topic
  ##########################################################################

  test 'delete_topic removes a topic the viewer started' do
    login_as user
    discussion = create_topic

    assert_difference 'Platform::ForumTopic.count', -1 do
      post :delete_topic, params: {topic_id: discussion.id, source_url: source_url,
                                   authenticity_token: form_authenticity_token}
    end

    assert_redirected_to source_url
    assert_match 'has been removed', flash[:trfn]
  end

  test 'delete_topic will not remove somebody else\'s topic' do
    discussion = create_topic(create_user('Author'))
    login_as user

    assert_no_difference 'Platform::ForumTopic.count' do
      post :delete_topic, params: {topic_id: discussion.id, source_url: source_url,
                                   authenticity_token: form_authenticity_token}
    end

    assert_redirected_to source_url
    assert_match "didn't create", flash[:trfe]
  end

  test 'delete_topic reports a topic that does not exist' do
    login_as user

    post :delete_topic, params: {topic_id: 0, source_url: source_url,
                                 authenticity_token: form_authenticity_token}
    assert_redirected_to source_url
    assert_match 'does not exist', flash[:trfe]
  end

  test 'delete_topic does not remove anything over GET' do
    login_as user
    discussion = create_topic

    assert_no_difference 'Platform::ForumTopic.count' do
      get :delete_topic, params: {topic_id: discussion.id, source_url: source_url}
    end

    assert_redirected_to source_url
  end

  ##########################################################################
  #### delete_message
  ##########################################################################

  test 'delete_message removes a message the viewer posted' do
    login_as user
    posted = create_message(create_topic)

    assert_difference 'Platform::ForumMessage.count', -1 do
      post :delete_message, params: {message_id: posted.id, source_url: source_url,
                                     authenticity_token: form_authenticity_token}
    end

    assert_redirected_to source_url
    assert_match 'has been removed', flash[:trfn]
  end

  test 'delete_message will not remove somebody else\'s message' do
    author = create_user('Author')
    posted = create_message(create_topic(author), 'Not yours', author)
    login_as user

    assert_no_difference 'Platform::ForumMessage.count' do
      post :delete_message, params: {message_id: posted.id, source_url: source_url,
                                     authenticity_token: form_authenticity_token}
    end

    assert_redirected_to source_url
    assert_match "didn't post", flash[:trfe]
  end

  test 'delete_message reports a message that does not exist' do
    login_as user

    post :delete_message, params: {message_id: 0, source_url: source_url,
                                   authenticity_token: form_authenticity_token}
    assert_redirected_to source_url
    assert_match 'does not exist', flash[:trfe]
  end

  ##########################################################################
  #### redirect_to_source -- Platform::BaseController, reached from here
  ##########################################################################

  test 'redirect_to_source prefers the source_url parameter' do
    login_as user
    @request.env['HTTP_REFERER'] = 'http://referer.example.com/page'

    post :delete_topic, params: {topic_id: 0, source_url: source_url,
                                 authenticity_token: form_authenticity_token}
    assert_redirected_to source_url
  end

  test 'redirect_to_source falls back to the referer' do
    login_as user
    @request.env['HTTP_REFERER'] = 'http://test.host/platform/apps'

    post :delete_topic, params: {topic_id: 0, authenticity_token: form_authenticity_token}
    assert_redirected_to 'http://test.host/platform/apps'
  end

  test 'redirect_to_source falls back to the site default url' do
    login_as user

    post :delete_topic, params: {topic_id: 0, authenticity_token: form_authenticity_token}
    assert_redirected_to Platform::Config.default_url
  end

  # params[:source_url] is request input and the referer is sent by the client, so neither is
  # allowed to send the viewer off this site.  Rails 7 turned this from an open redirect into a
  # 500; dropping the value and falling back is what it should have been doing.
  test 'redirect_to_source refuses a source_url on another host' do
    login_as user

    post :delete_topic, params: {topic_id: 0, source_url: 'http://evil.example.com/phish',
                                 authenticity_token: form_authenticity_token}
    assert_redirected_to Platform::Config.default_url
  end

  test 'redirect_to_source refuses a referer on another host' do
    login_as user
    @request.env['HTTP_REFERER'] = 'http://evil.example.com/phish'

    post :delete_topic, params: {topic_id: 0, authenticity_token: form_authenticity_token}
    assert_redirected_to Platform::Config.default_url
  end

  test 'redirect_to_source takes a bare path' do
    login_as user

    post :delete_topic, params: {topic_id: 0, source_url: '/platform/apps/1',
                                 authenticity_token: form_authenticity_token}
    assert_redirected_to '/platform/apps/1'
  end

  test 'redirect_to_source ignores a source_url that is not a url at all' do
    login_as user

    post :delete_topic, params: {topic_id: 0, source_url: 'http://[not a url',
                                 authenticity_token: form_authenticity_token}
    assert_redirected_to Platform::Config.default_url
  end

  # The referer is still used when the source_url is refused: they are checked in order and the
  # first one that is on this host wins.
  test 'redirect_to_source falls through an off-host source_url to an acceptable referer' do
    login_as user
    @request.env['HTTP_REFERER'] = 'http://test.host/platform/apps'

    post :delete_topic, params: {topic_id: 0, source_url: 'http://evil.example.com/phish',
                                 authenticity_token: form_authenticity_token}
    assert_redirected_to 'http://test.host/platform/apps'
  end

private

  def source_url
    'http://test.host/platform/apps/1'
  end

  def create_topic(author = nil)
    Platform::ForumTopic.create!(user: author || user, subject: app, topic: 'A topic')
  end

  def create_message(topic, body = 'A message', author = nil)
    Platform::ForumMessage.create!(topic: topic, message: body, user: author || user)
  end

end # class Platform::ForumControllerTest
