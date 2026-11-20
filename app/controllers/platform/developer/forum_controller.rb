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

module Platform
  module Developer
    class ForumController < BaseController

      skip_before_action :validate_guest_user
      skip_before_action :validate_developer

      protect_from_forgery only: [:topic, :delete_topic, :delete_message]

      # The site-wide topics -- the ones with no subject.  A topic with a subject belongs to an
      # application and is listed on that application's page by Platform::AppsController#view.
      #
      # The call was will_paginate's Rails 2 signature (:all plus :conditions and :order), which
      # has raised ArgumentError since will_paginate 3, so the developer forum has not listed
      # anything in a very long time.  The return value still has to be a will_paginate
      # collection: index.html.erb reads #total_pages off it through will_paginate().
      def index
        @topics = Platform::ForumTopic.where(subject_id: nil)
                                      .order('created_at desc')
                                      .paginate(page: page, per_page: per_page)
      end

      def topic
        if request.post? and verified_request?
          return validate_guest_user if platform_current_user_is_guest?

          if params[:topic_id]
            topic = Platform::ForumTopic.find_by_id(params[:topic_id])
          else
            topic = Platform::ForumTopic.create(user: platform_current_user, topic: params[:topic])
          end

          Platform::ForumMessage.create(topic: topic, message: params[:message], user: platform_current_user)
          return redirect_to(action: :topic, topic_id: topic.id, last_page: true)
        end

        # @topic may be nil -- no :topic_id, or one that names nothing -- and topic.html.erb
        # already handles that by offering the new-topic form.  The body below did not: it asked
        # a nil for its #post_count and its #id.  Same Rails 2 paginate signature as #index.
        unless params[:mode] == "create"
          @topic = Platform::ForumTopic.find_by_id(params[:topic_id])
          return unless @topic

          if params[:last_page]
            params[:page] = (@topic.post_count / per_page.to_i)
            params[:page] += 1 unless (@topic.post_count % per_page.to_i == 0)
            params[:page] = 1 if params[:page] == 0
          end

          @messages = Platform::ForumMessage.where(forum_topic_id: @topic.id)
                                            .order('created_at asc')
                                            .paginate(page: page, per_page: per_page)
        end
      end

      def delete_topic
        return validate_guest_user if platform_current_user_is_guest?

        topic = Platform::ForumTopic.find_by_id(params[:topic_id])

        if request.post? and verified_request?
          # `topic.destroy if topic` further down says this was known to be nilable, but the
          # authorship check above it asked the same nil for its #user first.
          unless topic
            trfe("This topic does not exist")
            return redirect_to(action: :index)
          end

          if topic.user != platform_current_user
            trfe("You cannot delete topics you didn't create.")
            return redirect_to(action: :index)
          end

          topic.destroy
          trfn("The topic {topic} has been removed", 'Developer Forum', topic: "\"#{Platform.escape_html(topic.topic)}\"")
        end

        redirect_to(action: :index)
      end

      def delete_message
        return validate_guest_user if platform_current_user_is_guest?

        message = Platform::ForumMessage.find_by_id(params[:message_id])

        # Hoisted out of the POST branch: the redirect at the bottom asks the message for its
        # topic whatever the method, so a GET naming nothing was a NoMethodError on nil.
        unless message
          trfe("This message does not exist")
          return redirect_to(action: :index)
        end

        if request.post? and verified_request?
          if message.user != platform_current_user
            trfe("You cannot delete messages you didn't post.")
            # Two things.  `return`, because without it the branch printed its error and then
            # fell straight through to the destroy below -- the authorship check rejected the
            # request and deleted the message anyway.  And #topic, because
            # #language_forum_topic is tr8n's association, not this model's, so building the
            # redirect raised NoMethodError and never got as far as answering.
            return redirect_to(action: :topic, topic_id: message.topic.id)
          end

          message.destroy
          trfn("The message has been removed")
        end

        redirect_to(action: :topic, topic_id: message.topic.id)
      end

    end # class ForumController
  end # module Developer
end # module Platform
