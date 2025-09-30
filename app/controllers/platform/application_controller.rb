module Platform
  class ApplicationController < ::ApplicationController
    include Tr8n::CommonMethods

  private

    def user_class
      Platform::Config.user_class_name.constantize
    end

  end # class ApplicationController
end # module Platform
