class Comment < ActiveRecord::Base
  belongs_to :parent, :class_name => 'Content'
  
  # simplest case: just index all fields of this model:
  # acts_as_ferret
  
  # we use :store_class_name => true so that we can use 
  # the multi_search method to run queries across multiple
  # models (where each model has it's own index directory)
  acts_as_ferret :store_class_name => true

  # only index the named fields:
  #acts_as_ferret :fields => ['author', 'content' ]

  # you can override the default to_doc method 
  # to customize what gets into your index. 
  def to_doc
    # doc now has all the fields of our model instance, we 
    # just add another field to it:
    doc = super
    # add a field containing the current time
    doc <<  Ferret::Document::Field.new(
              'added', Time.now.to_i.to_s, 
              Ferret::Document::Field::Store::YES, 
              Ferret::Document::Field::Index::UNTOKENIZED)
    return doc
  end
end
