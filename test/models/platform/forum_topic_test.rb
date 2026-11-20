require 'test_helper'

module Platform
  class ForumTopicTest < Platform::TestCase

    test 'a topic belongs to its author and to a polymorphic subject' do
      topic = Platform::ForumTopic.create!(user: user, subject: app, topic: 'Does this work?')

      assert_equal user.id, topic.reload.user.id
      assert_equal 'Platform::Application', topic.subject_type
      assert_equal app, topic.subject
    end

    # The site-wide developer forum is the topics with no subject, which is why subject_id and
    # subject_type are nullable.  Rails 5 made belongs_to required by default, so this was
    # "Subject must exist" and no site-wide topic could be saved -- see the :optional on the
    # association.
    test 'a topic does not need a subject' do
      topic = Platform::ForumTopic.create!(user: user, topic: 'Site wide')

      assert_nil topic.reload.subject
      assert_nil topic.subject_id
      assert_nil topic.subject_type
    end

    test 'topic text is required' do
      assert_raise ActiveRecord::NotNullViolation do
        Platform::ForumTopic.create!(user: user, subject: app)
      end
    end

    ##########################################################################
    #### last_post and post_count
    ##########################################################################

    test 'last_post returns the most recently created message' do
      topic = Platform::ForumTopic.create!(user: user, subject: app, topic: 'T')
      post_message(topic, 'first',  3.days.ago)
      post_message(topic, 'newest', 1.day.ago)
      post_message(topic, 'middle', 2.days.ago)

      assert_equal 'newest', topic.last_post.message
    end

    test 'last_post is nil on a topic with no messages' do
      topic = Platform::ForumTopic.create!(user: user, subject: app, topic: 'T')

      assert_nil topic.last_post
    end

    test 'last_post only considers this topic' do
      mine   = Platform::ForumTopic.create!(user: user, subject: app, topic: 'Mine')
      theirs = Platform::ForumTopic.create!(user: user, subject: app, topic: 'Theirs')
      post_message(theirs, 'not mine', 1.minute.ago)

      assert_nil mine.last_post
      assert_equal 'not mine', theirs.last_post.message
    end

    test 'last_post is memoized' do
      topic = Platform::ForumTopic.create!(user: user, subject: app, topic: 'T')
      post_message(topic, 'first', 2.days.ago)
      assert_equal 'first', topic.last_post.message

      post_message(topic, 'second', 1.day.ago)
      assert_equal 'first', topic.last_post.message, 'the memoized value is kept until the topic is reloaded'
    end

    ##########################################################################

    # This called count() with the Rails 2 two-argument finder signature, which
    # ActiveRecord::Calculations#count does not accept, so it raised ArgumentError on every call
    # whatever the data.
    test 'post_count counts the messages on the topic' do
      topic = Platform::ForumTopic.create!(user: user, subject: app, topic: 'T')
      post_message(topic, 'one', 2.days.ago)
      post_message(topic, 'two', 1.day.ago)

      assert_equal 2, topic.post_count
    end

    test 'post_count is zero on a topic with no messages' do
      topic = Platform::ForumTopic.create!(user: user, subject: app, topic: 'T')

      assert_equal 0, topic.post_count
    end

    test 'post_count only counts this topic' do
      mine   = Platform::ForumTopic.create!(user: user, subject: app, topic: 'Mine')
      theirs = Platform::ForumTopic.create!(user: user, subject: app, topic: 'Theirs')
      post_message(theirs, 'not mine', 1.minute.ago)

      assert_equal 0, mine.post_count
      assert_equal 1, theirs.post_count
    end

    # The memoisation holds a zero, which is the case `||=` would get wrong in a language where
    # zero is falsey.  In Ruby it is not, so a topic with no posts does not re-query.
    test 'post_count is memoized, including a zero' do
      topic = Platform::ForumTopic.create!(user: user, subject: app, topic: 'T')
      assert_equal 0, topic.post_count

      post_message(topic, 'added later', 1.minute.ago)

      assert_equal 0, topic.post_count, 'the memoized zero is kept until the topic is reloaded'
    end

private

    def post_message(topic, message, created_at)
      Platform::ForumMessage.create!(topic: topic, user: user, message: message,
                                     created_at: created_at)
    end

  end # class ForumTopicTest
end # module Platform
