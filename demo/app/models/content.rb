class Content < ActiveRecord::Base
  has_many :comments
  
  # a higher boost means more importance for the field --> documents having a
  # match in a field with a higher boost value will be ranked better
  #
  # we use the store_class_name flag to be able to retrieve model instances when
  # searching multiple indexes at once.
  acts_as_ferret :fields => { :comment_count => {}, 'title' => { :boost => 2 }, 'description' => { :boost => 1 }, :special => {} }, :store_class_name => true

  # use this instead to not assign special boost values:
  #acts_as_ferret :fields => [ 'title', 'description' ]

  # returns the number of comments attached to this content.
  # the value returned by this method will be indexed, too.
  def comment_count
    comments.size
  end
end
