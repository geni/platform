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
  module Admin
    class CategoriesController < Admin::BaseController

      def index
        @root = Platform::Category.root
        @category = Platform::Category.find(params[:category_id]) if params[:category_id]
        @category ||= @root
      end

      def tree
        @root = Platform::Category.root
        @category = Platform::Category.find(params[:category_id]) if params[:category_id]
        @category ||= @root
        render :layout => false
      end

      def items
        @parent = Platform::Category.find(params[:parent_id])
        @children = @parent.children
        @featured_apps = @parent.featured_application_categories
        @apps = @parent.regular_application_categories

        render :layout => false
      end

      def lb_update_category
        @parent = Platform::Category.find(params[:parent_id]) if params[:parent_id]
        @category = Platform::Category.find(params[:category_id]) if params[:category_id]
        @category = Platform::Category.new(:parent_id=>params[:parent_id]) unless @category
        render :layout => false
      end

      def update_category
        if request.post? and verified_request?
          if params[:category] && params[:category][:id].present?
            @category = Platform::Category.find(params[:category][:id])
            @category.update_attributes(params[:category])
          else
            @category = Platform::Category.create(params[:category])
          end
        end

        redirect_to :action => :index, :category_id => @category.id
      end

      def lb_update_application_category
        @app_cat = Platform::ApplicationCategory.find_by_category_id_and_application_id(params[:category_id], params[:app_id])
        render :layout => false
      end

      def update_application_category
        app_cat = Platform::ApplicationCategory.find(params[:application_category][:id])

        if request.post? and verified_request?
          app_cat.update_attributes(params[:application_category])
        end

        redirect_to :action => :index, :category_id => app_cat.category.id
      end

      def delete_category
        if request.post? and verified_request?
          recursive_category_delete(params[:category_id])
        end

        redirect_to :action => :index
      end

      def assign_category
        app = Platform::Application.find_by_id(params[:app_id])
        category = Platform::Category.find(params[:category_id])

        if request.post? and verified_request?
          if params[:checked] == "true"
            cat = category
            while cat do
              app.add_category(cat) unless cat.root?
              cat = cat.parent
            end
          else
            app.remove_category(category)
          end
          app.reload
        end

        render(:partial=>"/platform/admin/apps/categories", :locals => {:app => app})
      end

      def category_assigner
        @app = Platform::Application.find_by_id(params[:app_id])
        render :layout=>false
      end

      def category_assigner_tree
        @app = Platform::Application.find_by_id(params[:app_id])
        @root_keyword = params[:root_keyword] || "root"
        @root = Platform::Category.find_by_keyword(@root_keyword)

        render :layout=>false
      end

      def update_featured_flag
        app_cat = Platform::ApplicationCategory.find(params[:app_category_id])

        if request.post? and verified_request?
          app_cat.update_attributes(:featured => params[:checked])
        end

        render(:partial=>"/platform/admin/apps/categories", :locals => {:app => app_cat.application})
      end

    private

      def recursive_category_delete(cat_id)
        cat = Platform::Category.find(cat_id)
        Platform::ApplicationCategory.delete_all(["category_id=?", cat_id])

        cat.children.each do |sub_cat|
          recursive_category_delete(sub_cat.id)
        end

        cat.destroy
      end

    end # class CategoriesController
  end # module Admin
end # module Platform
