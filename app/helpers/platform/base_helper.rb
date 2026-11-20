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
  module BaseHelper

    def platform_user_login_tag(opts = {})
      opts[:class] ||= 'tr8n_right_horiz_list'
      render(partial: '/platform/common/user_login', locals: {opts: opts})
    end

    # Where will_filter's javascript fetches its filter UI from.
    #
    # will_filter's own partials call will_filter_path, and every admin screen in this gem renders
    # one of them -- but the helper does not exist in a Platform view, so all five admin lists
    # were a NameError.  WillFilter::Engine is mounted inside Tr8n::Engine, which this engine
    # mounts in turn, and Rails only publishes a mounted engine's helpers to the route set that
    # did the mounting.  Going through the Tr8n proxy answers the same path without mounting the
    # engine a second time, which would change what a host application exposes.
    def will_filter_path(*args)
      tr8n.will_filter_path(*args)
    end

    # The open/closed disclosure triangle in front of a collapsible section.  Renders both spans;
    # Platform.Effects.toggle swaps which one is hidden.
    #
    # Three things were wrong, and the first two compounded rather than cancelling out:
    #
    #   * the method assembled a String and handed it back, so ERB escaped the whole thing and
    #     every toggler on every page rendered its own markup as visible text;
    #   * the arrows were passed to link_to_function as the link text, and that is link_to, which
    #     escapes what it is given -- so "&#x25BC;" came out as "&amp;#x25BC;" and would still
    #     have shown as the literal characters once the escaping above was fixed.  #toggler_arrow
    #     marks the entity safe, which is what makes it render as an arrow;
    #   * content_id and label were interpolated into markup unescaped.  That did not matter
    #     while the result was being escaped wholesale, and does now: content_tag escapes the id
    #     attribute, #toggler_arrow escapes the label, and the javascript the two links call is
    #     built with escape_javascript.
    def platform_toggler_tag(content_id, label = "", open = true, opts = {})
      style = opts[:style] || 'text-align:center;vertical-align:middle;'
      style = style + ';text-decoration:none;'

      toggle = "Platform.Effects.toggle('#{escape_javascript(content_id.to_s)}_open'," \
               "'#{escape_javascript(content_id.to_s)}_closed'," \
               "'#{escape_javascript(content_id.to_s)}')"

      safe_join([
        content_tag(:span, toggler_arrow('&#x25BC;', label, toggle, style),
                    id: "#{content_id}_open", style: (open ? nil : 'display:none')),
        content_tag(:span, toggler_arrow('&#x25BA;', label, toggle, style),
                    id: "#{content_id}_closed", style: (open ? 'display:none' : nil)),
      ])
    end

    def platform_documentation_tag(url_options = {})
      link_to(image_tag("/platform/images/bullet_go.png", style: "vertical-align:middle;"), url_options.merge({controller: "/platform/developer/help", action: "api"}))
    end

    def platform_documentation_field_decorators_tag(field)
      return unless field[:status]
      return image_tag("/platform/images/cancel.png", style: "vertical-align:top;height:10px;", title: trl("This field has been deprecated and will no longer be supported in the future versions")) if ['deprecated', 'removed'].include?(field[:status])
      return image_tag("/platform/images/exclamation.png", style: "vertical-align:top;height:10px;", title: trl("This field will be changed in the future versions")) if field[:status] == 'changed'
      return image_tag("/platform/images/add.png", style: "vertical-align:top;height:10px;", title: trl("This field has been added")) if field[:status] == 'added'
      return image_tag("/platform/images/accept.png", style: "vertical-align:top;height:10px;", title: trl("This field has been changed")) if field[:status] == 'updated'
    end

    def platform_documentation_api_decorators_tag(api)
      return unless api[:status]
      return image_tag("/platform/images/exclamation.png", style: "vertical-align:top;height:10px;", title: trl("The API structure has changed")) if ['changed'].include?(api[:status])
      return image_tag("/platform/images/cancel.png", style: "vertical-align:top;height:10px;", title: trl("The API has been removed")) if ['removed', 'deprecated'].include?(api[:status])
      return image_tag("/platform/images/add.png", style: "vertical-align:top;height:10px;", title: trl("This API has been added")) if api[:status] == 'added'
      return image_tag("/platform/images/accept.png", style: "vertical-align:top;height:10px;", title: trl("This API has been updated")) if api[:status] == 'updated'
    end

    def platform_scripts_tag(opts = {})
      render(partial: '/platform/common/scripts', locals: {opts: opts})
    end

    def platform_app_rank_tag(app, rank = nil, opts = {})
      return "" unless app

      rank ||= app.rank || 0
      rank = rank * 100 / 5

      html = "<span dir='ltr'>".dup
      1.upto(5) do |i|
        if rank > i * 20 - 10  and rank < i * 20
          html << image_tag("/tr8n/images/rating_star05.png")
        elsif rank < i * 20 - 10
          html << image_tag("/tr8n/images/rating_star0.png")
        else
          html << image_tag("/tr8n/images/rating_star1.png")
        end
      end
      html << "</span>"
      html.html_safe
    end

    def platform_rating_tag(rating, opts = {})
      return "" unless rating

      value = rating.value || 0
      style = []
      style << "width:#{opts[:width]}" if opts[:width]

      html = "<span dir='ltr'>"
      1.upto(5) do |i|
        if i <= value
          html << image_tag("/tr8n/images/rating_star1.png", style: style.join(";"))
        else
          html << image_tag("/tr8n/images/rating_star0.png", style: style.join(";"))
        end
      end
      html << "</span>"
      html.html_safe
    end

    def platform_spinner_tag(id = "spinner", label = nil, cls='spinner')
      html = "<div id='#{id}' class='#{cls}' style='display:none'>"
      html << image_tag("/platform/images/spinner.gif", style: "vertical-align:middle;")
      html << " #{trl(label)}" if label
      html << "</div>"
    end

    def platform_user_tag(user, options = {})
      return "Deleted Translator" unless user

      link = Platform::Config.user_link(user) if options[:linked]

      if link
        link_to(Platform.escape_html(Platform::Config.user_name(user)), link)
      else
        Platform.escape_html(Platform::Config.user_name(user))
      end
    end

    def platform_user_mugshot_tag(user, options = {})
      if user and !Platform::Config.user_mugshot(user).blank?
        img_url = Platform::Config.user_mugshot(user)
      else
        img_url = Platform::Config.silhouette_image(user)
      end

      img_tag = "<img src='#{img_url}' style='width:48px'>"

      link = Platform::Config.user_link(user) if options[:linked]

      if user and link
        link_to(img_tag, link)
      else
        img_tag
      end

      img_tag.html_safe
    end

    def platform_help_icon_tag(path = "index", opts = {})
      link_to(image_tag("/platform/images/help.png", style: "border:0px; vertical-align:middle;", title: trl("Help")), opts.merge({controller: "/platform/developer/help", action: path}), target: "_new")
    end

  private

    # One arrow of a toggler.  The entity has to reach link_to already safe -- link_to escapes
    # its text -- and the caller's label has to be escaped before it joins it, or marking the
    # pair safe would carry the label's markup through.
    def toggler_arrow(entity, label, toggle, style)
      text = "#{entity} #{ERB::Util.html_escape(label)}".html_safe

      link_to_function(text, toggle, style: style)
    end

  end # module BaseHelper
end # module Platform
