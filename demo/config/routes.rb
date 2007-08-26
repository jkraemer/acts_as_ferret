ActionController::Routing::Routes.draw do |map|

  map.resources :content
  map.resource :search


  # Install the default route as the lowest priority.
  map.connect ':controller/:action/:id'
end
