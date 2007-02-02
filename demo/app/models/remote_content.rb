class RemoteContent < ActiveRecord::Base
  acts_as_ferret( :name => :content, :remote => 'druby://localhost:9909', 
                  :fields => { 
                    :title         => { :boost => 2 }, # boost is ignored here, for now
                    :description   => { :boost => 1, :store => :yes },
                  })

end
