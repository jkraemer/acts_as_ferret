class Comment < ActiveRecord::Base
  belongs_to :parent, :class_name => 'Content'
  acts_as_ferret :fields => [ 'author', 'content' ]
end
