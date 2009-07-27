ActionController::Routing::Routes.draw do |map|
 
  map.resource :account, :controller => "users"
  map.resource :user_session
  map.resources :users
  map.signup 'signup', :controller => 'users', :action => 'new'
  map.signin 'signin', :controller => 'user_sessions', :action => 'new'
  map.signout 'signout', :controller => 'user_sessions', :action => 'destroy'
 
  map.resources :notes, :collection => { :search => [:get, :post] }
  map.resources :notes
  map.root :controller => 'notes', :action => 'index'
 
  # general activities
  # map.admin 'admin', :controller => 'notes', :action => 'admin'
 
  map.connect ':controller/:action/:id'
  map.connect ':controller/:action/:id.:format'

end

