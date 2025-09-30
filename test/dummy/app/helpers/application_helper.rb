module ApplicationHelper

  def switch_user_links
    links = []

    User.all.each do |user|
      if user.id == current_user.id
        links << "<b>#{user.name}</b>"
      else
        links << link_to(user.name, switch_user_path(user_id: user.id))
      end
    end

    links.join(" | ").html_safe
  end

end # module ApplicationHelper
