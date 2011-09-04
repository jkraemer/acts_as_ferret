Demo::Application.routes.draw do
  resources :contents
  match 'search', :to => 'searches#search'


  # Install the default route as the lowest priority.
  match ':controller(/:action(/:id))'
end
