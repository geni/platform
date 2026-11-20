require 'test_helper'

module Platform
  # A reply on a forum topic.
  #
  # This model declared a bare `belongs_to :topic`, which had Rails look for a Platform::Topic
  # class and a topic_id column -- neither of which exists.  Rails resolves a belongs_to class
  # lazily, so building a record was fine and only validation raised, which meant no forum message
  # could be saved through this model at all.  The association keeps its name and now says which
  # class and column it means.
  class ForumMessageTest < Platform::TestCase

    ##########################################################################
    #### The topic association
    ##########################################################################

    test 'a message belongs to its topic and author' do
      message = Platform::ForumMessage.create!(user: user, topic: topic, message: 'hi')

      assert_equal topic.id, message.reload.topic.id
      assert_equal user.id,  message.user.id
    end

    # The column is forum_topic_id; there is no topic_id.  Assigning the association has to write
    # that column, and assigning the column has to resolve the association.
    test 'the association reads and writes forum_topic_id' do
      message = Platform::ForumMessage.create!(user: user, topic: topic, message: 'hi')

      assert_equal topic.id, message.forum_topic_id
      assert_equal false, Platform::ForumMessage.column_names.include?('topic_id')
    end

    test 'the topic can be set by its foreign key' do
      message = Platform::ForumMessage.create!(user: user, forum_topic_id: topic.id, message: 'hi')

      assert_equal topic.id, message.reload.topic.id
    end

    test 'the association resolves to ForumTopic, not a Topic class' do
      reflection = Platform::ForumMessage.reflect_on_association(:topic)

      assert_equal 'Platform::ForumTopic', reflection.class_name
      assert_equal Platform::ForumTopic, reflection.klass
      assert_equal 'forum_topic_id', reflection.foreign_key.to_s
    end

    # #topic on a message is a record; #topic on a ForumTopic is the subject text.  Keeping the
    # association name meant keeping that collision, so it is worth stating outright.
    test 'a message topic is a record while a topic topic is its text' do
      message = Platform::ForumMessage.create!(user: user, topic: topic, message: 'hi')

      assert_kind_of Platform::ForumTopic, message.topic
      assert_equal 'Does this work?', message.topic.topic
    end

    test 'both the topic and the author are required' do
      assert_raise ActiveRecord::RecordInvalid do
        Platform::ForumMessage.create!(user: user, message: 'no topic')
      end

      assert_raise ActiveRecord::RecordInvalid do
        Platform::ForumMessage.create!(topic: topic, message: 'no author')
      end
    end

    test 'a topic can carry several messages' do
      first  = Platform::ForumMessage.create!(user: user, topic: topic, message: 'first')
      second = Platform::ForumMessage.create!(user: user, topic: topic, message: 'second')

      assert_equal [first.id, second.id].sort,
                   Platform::ForumMessage.where(forum_topic_id: topic.id).map(&:id).sort
    end

    ##########################################################################
    #### toHTML
    ####
    #### Touches no association, so it works on an unsaved record too.
    ##########################################################################

    test 'toHTML escapes the message and turns newlines into breaks' do
      message = Platform::ForumMessage.new(message: "<script>x</script> & co\nsecond line")

      assert_equal '&lt;script&gt;x&lt;/script&gt; &amp; co<br>second line', message.toHTML
    end

    test 'toHTML turns every newline into a break, not just the first' do
      assert_equal 'a<br>b<br>c', Platform::ForumMessage.new(message: "a\nb\nc").toHTML
    end

    test 'toHTML is blank when there is no message' do
      assert_equal '', Platform::ForumMessage.new.toHTML
    end

private

    def topic
      @topic ||= Platform::ForumTopic.create!(user: user, subject: app, topic: 'Does this work?')
    end

  end # class ForumMessageTest
end # module Platform
