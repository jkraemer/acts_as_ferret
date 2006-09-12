# common base class for Content and SpecialContent
class ContentBase < ActiveRecord::Base
  set_table_name 'contents'

  # a higher boost means more importance for the field --> documents having a
  # match in a field with a higher boost value will be ranked higher
  #
  # we use the store_class_name flag to be able to retrieve model instances when
  # searching multiple indexes at once.
  # the contents of the description field are stored in the index for running
  # 'more like this' queries to find other content instances with similar
  # descriptions
  acts_as_ferret( :fields => { 
    :comment_count => {},
    :title         => { :boost => 2 }, 
    :description   => { :boost => 1, :store => :yes },
    :special       => {} 
  }, :store_class_name => true)


  def comment_count; 0 end

end

class Content < ContentBase #ActiveRecord::Base

  has_many :comments

  # returns the number of comments attached to this content.
  # the value returned by this method will be indexed, too.
  def comment_count
    comments.size
  end
end
