class Comment < ActiveRecord::Base
  belongs_to :parent, :class_name => 'Content'
  # just index all fields:
  acts_as_ferret 
  #acts_as_ferret :fields => ['author', 'content' ]
end
