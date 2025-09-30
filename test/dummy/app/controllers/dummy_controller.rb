class DummyController < ApplicationController
  helper Tr8n::HelperMethods

  def index
    # render app/views/dummy/index.html.erb
  end

  def switch_user
    user = User.find_by(id: params[:user_id])
    if user
      session[:user_id] = user.id
      redirect_to root_path, notice: "Switched to user: #{user.name}"
    else
      redirect_to root_path, alert: "User not found"
    end
  end

end # class DummyController
