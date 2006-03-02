require 'ferret'

index = Ferret::Index::Index.new( :path => Content.class_index_dir,
																	:create => true
																)
Content.find_all.each { |content| index << content.to_doc }
index.flush
index.optimize
index.close

