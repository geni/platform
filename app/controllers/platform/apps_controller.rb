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
  class AppsController < BaseController

    def index
      unless Platform::Config.enable_app_directory?
        return redirect_to(:controller=>"/platform/developer/apps", :action=>"index")
      end

      @categories = Platform::Category.root.children
      @category = Platform::Category.find(params[:cat_id]) if params[:cat_id]
      @category = @categories.first unless @category

      @featured_apps = []
      @apps = []
      @search_apps = []

      if params[:search].blank?
        @featured_apps = Platform::Application.featured_for_category(@category, page, Platform::Config.featured_apps_per_page)
        @apps = Platform::Application.regular_for_category(@category, page, Platform::Config.suggested_apps_per_page)
      else
        @category = nil
        @search_apps = searched_apps
      end
    end

    def view
      @app = Platform::Application.find(params[:id])
      @sections = ["Info", "Reviews", "Discussions"]
      @section = params[:sec] || "Info"
      # Every paginate call in this controller was will_paginate's Rails 2 signature -- :all plus
      # :conditions and :order -- which it has raised ArgumentError on since version 3.  So the
      # application directory, every application's page, and the reviews and discussions on it
      # were all a 500.  The return values still have to be will_paginate collections: the
      # paginator partials read #current_page, #total_pages, #previous_page and #next_page.
      @ratings = Platform::Rating.where(object_type: @app.class.name, object_id: @app.id)
                                 .order('updated_at desc')
                                 .paginate(page: page, per_page: per_page)

      params[:sec] ||= 'Info'
      if params[:sec] == 'Discussions'
        @topic = Platform::ForumTopic.find_by_id(params[:topic_id]) if params[:topic_id]

        # Branch on the topic rather than on the parameter, because view.html.erb does: with no
        # topic to show it renders the topic list, and a :topic_id naming nothing used to leave
        # @topics unset for it -- after asking the missing topic for its #post_count and its #id.
        if @topic
          if params[:last_page]
            params[:page] = (@topic.post_count / per_page.to_i)
            params[:page] += 1 unless (@topic.post_count % per_page.to_i == 0)
            params[:page] = 1 if params[:page] == 0
          end

          @messages = Platform::ForumMessage.where(forum_topic_id: @topic.id)
                                            .order('created_at asc')
                                            .paginate(page: page, per_page: per_page)
        else
          @topics = Platform::ForumTopic.where(subject_type: @app.class.name, subject_id: @app.id)
                                        .order('created_at desc')
                                        .paginate(page: page, per_page: per_page)
        end
      end
    end

    def paginate_module
      if params[:module] == 'featured_apps'
        category = Platform::Category.find(params[:cat_id])
        apps = Platform::Application.featured_for_category(category, page, Platform::Config.featured_apps_per_page)
        render(:partial => 'featured_apps_module', :locals => {:apps => apps, :per_row => Platform::Config.featured_apps_per_row})
      elsif params[:module] == 'suggested_apps'
        category = Platform::Category.find(params[:cat_id])
        apps = Platform::Application.regular_for_category(category, page, Platform::Config.suggested_apps_per_page)
        render(:partial => 'apps_module', :locals => {:apps => apps, :per_row => Platform::Config.suggested_apps_per_row})
      else
        render(partial: 'search_apps_module', locals: {apps: searched_apps})
      end
    end

    # Four actions have been removed from here, all of them unreachable or useless:
    #
    #   #method_missing, the embedded canvas application page, and its canvas_app template.
    #     Rails dispatches an unknown action to #action_missing, never to #method_missing -- and
    #     no unknown action name reached this controller anyway: /platform/apps/<canvas_name>,
    #     the URL Platform::Application#app_url advertises, matches
    #     `get '/apps/:id' => 'apps#view'` and arrives as an :id.  The template had rotted to
    #     match, calling URI.escape (removed in Ruby 3.0) and defining its resizeFrame callback
    #     inside a javascript_tag block whose output was discarded.
    #
    #   #xd and its template, the other half of that resize handshake: it called
    #     parent.parent.resizeFrame, which the canvas_app template was the only definition of.
    #
    #   #featured_applications_module_content, which had no template of that name and so could
    #     only answer MissingTemplate.  #paginate_module above does the job it looks like it was
    #     meant to do, and does it with the pagination _featured_apps_module needs.
    #
    #   #apps_page, which returned params[:section] -- a parameter nothing sends; #view reads
    #     params[:sec] and the directory's javascript sends :module.
    #
    # platform_applications.canvas_name and .canvas_url, the canvas fields on the developer and
    # admin forms, and #app_url are all left as they are: deciding what embedded applications
    # should look like is separate work from removing code that has never run.

  private

    # The applications matching params[:search], for #index and for the paginated reload of the
    # same list in #paginate_module -- which had its own copy of the query.
    def searched_apps
      Platform::Application.where('name like :pattern or description like :pattern',
                                  pattern: "%#{params[:search]}%")
                           .order('name asc')
                           .paginate(page: page, per_page: Platform::Config.searched_apps_per_page)
    end

  end # class AppsController
end # module Platform
