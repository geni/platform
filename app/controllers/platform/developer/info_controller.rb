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
    class InfoController < BaseController

      def index
      end

      def update_section
        unless request.post? and verified_request?
          return render(:partial => params[:section], :locals => {:mode => params[:mode].to_sym})
        end

        platform_current_developer.update(developer_params)

        platform_current_developer.reload
        render(:partial => params[:section], :locals => {:mode => :view})
      end

    private

      # params[:developer] is ActionController::Parameters, and handing those straight to #update
      # is ActiveModel::ForbiddenAttributesError -- so saving this page has not worked since
      # strong parameters arrived.
      #
      # The five fields are the ones the form in _basic_info renders.  user_id is deliberately not
      # among them: it is the account the developer record belongs to, and mass-assigning it would
      # move the record -- and every application under it -- onto somebody else's account.
      def developer_params
        params.require(:developer).permit(:name, :email, :url, :phone, :about)
      end

    end # class InfoController
  end # module Developer
end # module Platform
