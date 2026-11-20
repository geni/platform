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
    class DevelopersController < Admin::BaseController

      def index
        # Platform::Developer::Developer, not Platform::Developer: the latter is the module, which
        # has no .filter, so this raised NoMethodError and the admin developer list never rendered.
        @developers = Platform::Developer::Developer.filter(params: params, filter: Platform::DeveloperFilter)
      end

      # The same mistake #index had, three more times: Platform::Developer is the module the model
      # lives in and has no .find_by_id, so viewing or editing a developer raised NoMethodError.
      def view
        @dev = Platform::Developer::Developer.find_by_id(params[:dev_id])
      end

      def lb_edit
        @dev = Platform::Developer::Developer.find_by_id(params[:dev_id])
        render :layout => false
      end

      def update
        if request.post? and verified_request?
          dev = Platform::Developer::Developer.find_by_id(params[:dev_id]) if params[:dev_id]
          dev.update(developer_params) if dev
        end

        redirect_to_source(:action => :index)
      end

    private

      # params[:dev] is ActionController::Parameters, and handing those straight to #update is
      # ActiveModel::ForbiddenAttributesError.  The five fields are the ones lb_edit's form
      # renders; user_id is not among them, because reassigning it would move the developer --
      # and every application under it -- onto another account.
      def developer_params
        params.require(:dev).permit(:name, :about, :url, :email, :phone)
      end

    end # class DevelopersController
  end # module Admin
end # module Platform
