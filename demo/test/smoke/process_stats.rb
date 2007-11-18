require 'rubygems'
require 'gruff'

search = Stats.compute :search
write = Stats.compute :write

def chart(title)
  returning Gruff::Line.new do |g|
    g.title = title
    g.theme = {
      :background_colors => ["#e6e6e6", "#e6e6e6"],
      :colors => ["#ff43a7", '#666666', 'black', 'white', 'grey'],
      :marker_color => "white"
    }
  end
end

g = chart "aaf DRb (write performance)"
g.data :avg, write.map{|r| r[:avg]}
g.data :stddev, write.map{|r| r[:stddev]}
g.write "write_averages.png"

g = chart "aaf DRb (search performance)"
g.data :average, search.map{ |r| r[:avg] }
g.data :stddev, search.map{ |r| r[:stddev] }
g.write "search_averages.png"

g = chart "aaf DRb (search performance (medians))"
g.data :search_median, search.map{ |r| r[:median] }
g.write "search_medians.png"

