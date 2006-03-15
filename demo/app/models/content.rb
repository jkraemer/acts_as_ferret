class Content < ActiveRecord::Base
  has_many :comments
  
  # a higher boost means more importance for the field --> documents having a
  # match in a field with a higher boost value will be ranked better
  acts_as_ferret :fields => { 'title' => { :boost => 2 }, 'description' => { :boost => 1 } }, :store_class_name => true

  # use this instead to not assign special boost values:
  #acts_as_ferret :fields => [ 'title', 'description' ]
end
