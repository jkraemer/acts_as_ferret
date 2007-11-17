# Simple smoke test for the DRb server
# usage: 
#
# # start the DRb server
# script/ferret_server -e test start
#
# # run the script
# AAF_REMOTE=true script/runner -e test test/smoke/drb_smoke_test.rb


class DrbSmokeTest
  def initialize(id)
    @id = id
  end
  def run
    500.times do |i|
      Content.create! :title => "title #{i}", :description => "description #{i}"
      if i % 100 == 0
        puts "#{@id}: #{i} records indexed"
      end
    end
  end
end

def count_connections
  Content.connection.execute("show status where variable_name = 'Threads_connected'").fetch_row.last
end

10.times do |i|
  unless fork
    @id = i
    break
  end
end

if @id
  DrbSmokeTest.new(@id).run
else
  while true 
    puts "open connections: #{count_connections}"
    sleep 5
  end
end
