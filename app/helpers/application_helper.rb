# Methods added to this helper will be available to all templates in the application.
module ApplicationHelper
  def account_path
     return "/users/#{current_user.login}" if current_user
     return "/users"
  end
end

