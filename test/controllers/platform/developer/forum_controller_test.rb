require 'test_helper'

# The site-wide developer forum.  It skips both :validate_guest_user and :validate_developer, so a
# guest can read it -- but #topic, #delete_topic and #delete_message all check for a guest
# themselves before writing anything.
class Platform::Developer::ForumControllerTest < Platform::ControllerTestCase

  test 'index is reachable by a guest' do
    get :index
    assert_response :success
  end

  # Both forum post forms were written `<% form_tag do %>`, which discards what the block
  # captures -- so the forum rendered with no way to start a topic, and a topic with no way to
  # reply.
  test 'index offers the new topic form' do
    login_as user

    get :index
    assert_select 'form#forum_topic_form' do
      assert_select 'input[name=topic]'
      assert_select 'textarea[name=message]'
    end
  end

  # A guest may read the forum but not post to it, so the form is not offered to one.
  test 'index does not offer the new topic form to a guest' do
    get :index
    assert_select 'form#forum_topic_form', false
  end

  test 'index lists the site wide topics' do
    login_as user
    mine = create_topic('Mine')

    get :index
    assert_response :success
    assert_match 'Mine', response.body
    assert_equal [mine], assigned(:topics).to_a
  end

  # A topic with a subject belongs to that application and is listed on the application's own
  # page, not here.
  test 'index does not list an application\'s topics' do
    login_as user
    app_topic = Platform::ForumTopic.create!(user: user, topic: 'About the app', subject: app)

    get :index
    assert_response :success
    assert_not_includes assigned(:topics).to_a, app_topic
  end

  test 'index paginates' do
    login_as user
    3.times { |n| create_topic("Topic #{n}") }

    get :index, params: {per_page: 2}
    assert_equal 2, assigned(:topics).size
    assert_equal 3, assigned(:topics).total_entries
  end

  ##########################################################################
  #### topic -- read one, or post to it
  ##########################################################################

  test 'topic shows a topic and its messages' do
    login_as user
    discussion = create_topic
    create_message(discussion, 'First post')

    get :topic, params: {topic_id: discussion.id}
    assert_response :success
    assert_match 'First post', response.body
    assert_equal discussion, assigned(:topic)
  end

  test 'topic offers the reply form' do
    login_as user
    discussion = create_topic
    create_message(discussion, 'First post')

    get :topic, params: {topic_id: discussion.id}
    assert_select 'form#forum_topic_form' do
      assert_select 'textarea[name=message]'
    end
  end

  # topic.html.erb offers the new-topic form when there is no topic to show, so naming nothing is
  # a normal way to reach this page rather than an error.
  test 'topic with no topic_id offers the new topic form' do
    login_as user

    get :topic
    assert_response :success
    assert_nil assigned(:topic)
  end

  test 'topic with a topic_id that names nothing offers the new topic form' do
    login_as user

    get :topic, params: {topic_id: 0}
    assert_response :success
    assert_nil assigned(:topic)
  end

  test 'topic in create mode does not look a topic up' do
    login_as user

    get :topic, params: {mode: 'create'}
    assert_response :success
    assert_nil assigned(:topic)
  end

  # :last_page is how a reply gets back to where it landed: the page number is worked out from the
  # post count rather than passed in.
  test 'topic with last_page lands on the last page of messages' do
    login_as user
    discussion = create_topic
    3.times { |n| create_message(discussion, "Post #{n}") }

    get :topic, params: {topic_id: discussion.id, last_page: true, per_page: 2}
    assert_response :success
    assert_equal 2, @controller.params[:page]
  end

  test 'topic with last_page on a topic whose posts fill the page exactly' do
    login_as user
    discussion = create_topic
    2.times { |n| create_message(discussion, "Post #{n}") }

    get :topic, params: {topic_id: discussion.id, last_page: true, per_page: 2}
    assert_equal 1, @controller.params[:page]
  end

  test 'topic with last_page on an empty topic lands on page one' do
    login_as user
    discussion = create_topic

    get :topic, params: {topic_id: discussion.id, last_page: true, per_page: 2}
    assert_equal 1, @controller.params[:page]
  end

  test 'posting a topic starts it and posts the first message' do
    login_as user

    assert_difference ['Platform::ForumTopic.count', 'Platform::ForumMessage.count'] do
      post :topic, params: {topic: 'A new topic', message: 'Hello', authenticity_token: form_authenticity_token}
    end

    started = Platform::ForumTopic.order('id desc').first
    assert_redirected_to action: :topic, topic_id: started.id, last_page: true
    assert_equal 'A new topic', started.topic
    assert_equal user, started.user
    assert_equal 'Hello', started.last_post.message
    assert_equal user, started.last_post.user
  end

  test 'posting to an existing topic adds a message to it' do
    login_as user
    discussion = create_topic

    assert_no_difference 'Platform::ForumTopic.count' do
      assert_difference 'Platform::ForumMessage.count' do
        post :topic, params: {topic_id: discussion.id, message: 'A reply', authenticity_token: form_authenticity_token}
      end
    end

    assert_redirected_to action: :topic, topic_id: discussion.id, last_page: true
    assert_equal 'A reply', discussion.last_post.message
  end

  test 'a guest cannot post' do
    assert_no_difference 'Platform::ForumMessage.count' do
      post :topic, params: {topic: 'A new topic', message: 'Hello', authenticity_token: form_authenticity_token}
    end

    assert_redirected_to Platform::Config.default_url
  end

  ##########################################################################
  #### delete_topic
  ##########################################################################

  test 'delete_topic removes a topic the viewer started' do
    login_as user
    discussion = create_topic

    assert_difference 'Platform::ForumTopic.count', -1 do
      post :delete_topic, params: {topic_id: discussion.id, authenticity_token: form_authenticity_token}
    end

    assert_redirected_to action: :index
    assert_match 'has been removed', flash[:trfn]
  end

  test 'delete_topic will not remove somebody else\'s topic' do
    discussion = create_topic('Not yours', create_user('Author'))
    login_as user

    assert_no_difference 'Platform::ForumTopic.count' do
      post :delete_topic, params: {topic_id: discussion.id, authenticity_token: form_authenticity_token}
    end

    assert_redirected_to action: :index
    assert_match "didn't create", flash[:trfe]
  end

  test 'delete_topic reports a topic that does not exist' do
    login_as user

    post :delete_topic, params: {topic_id: 0, authenticity_token: form_authenticity_token}
    assert_redirected_to action: :index
    assert_match 'does not exist', flash[:trfe]
  end

  # A GET must not delete: a link or an image tag pointing here would be enough otherwise.
  test 'delete_topic does not remove anything over GET' do
    login_as user
    discussion = create_topic

    assert_no_difference 'Platform::ForumTopic.count' do
      get :delete_topic, params: {topic_id: discussion.id}
    end

    assert_redirected_to action: :index
  end

  test 'a guest cannot delete a topic' do
    discussion = create_topic('Mine', create_user('Author'))

    assert_no_difference 'Platform::ForumTopic.count' do
      post :delete_topic, params: {topic_id: discussion.id, authenticity_token: form_authenticity_token}
    end

    assert_redirected_to Platform::Config.default_url
  end

  ##########################################################################
  #### delete_message
  ##########################################################################

  test 'delete_message removes a message the viewer posted' do
    login_as user
    discussion = create_topic
    posted = create_message(discussion)

    assert_difference 'Platform::ForumMessage.count', -1 do
      post :delete_message, params: {message_id: posted.id, authenticity_token: form_authenticity_token}
    end

    assert_redirected_to action: :topic, topic_id: discussion.id
    assert_match 'has been removed', flash[:trfn]
  end

  test 'delete_message will not remove somebody else\'s message' do
    author = create_user('Author')
    discussion = create_topic('Theirs', author)
    posted = create_message(discussion, 'Not yours', author)
    login_as user

    assert_no_difference 'Platform::ForumMessage.count' do
      post :delete_message, params: {message_id: posted.id, authenticity_token: form_authenticity_token}
    end

    assert_redirected_to action: :topic, topic_id: discussion.id
    assert_match "didn't post", flash[:trfe]
  end

  test 'delete_message reports a message that does not exist' do
    login_as user

    post :delete_message, params: {message_id: 0, authenticity_token: form_authenticity_token}
    assert_redirected_to action: :index
    assert_match 'does not exist', flash[:trfe]
  end

  test 'delete_message does not remove anything over GET' do
    login_as user
    discussion = create_topic
    posted = create_message(discussion)

    assert_no_difference 'Platform::ForumMessage.count' do
      get :delete_message, params: {message_id: posted.id}
    end

    assert_redirected_to action: :topic, topic_id: discussion.id
  end

  test 'a guest cannot delete a message' do
    author = create_user('Author')
    posted = create_message(create_topic('Theirs', author), 'Not yours', author)

    assert_no_difference 'Platform::ForumMessage.count' do
      post :delete_message, params: {message_id: posted.id, authenticity_token: form_authenticity_token}
    end

    assert_redirected_to Platform::Config.default_url
  end

private

  def create_topic(subject = 'A topic', author = nil)
    Platform::ForumTopic.create!(user: author || user, topic: subject)
  end

  def create_message(topic, body = 'A message', author = nil)
    Platform::ForumMessage.create!(topic: topic, message: body, user: author || user)
  end

end # class Platform::Developer::ForumControllerTest
