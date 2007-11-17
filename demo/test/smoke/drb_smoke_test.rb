# Simple smoke test for the DRb server
# usage: 
#
# # start the DRb server
# script/ferret_server -e test start
#
# # run the script
# AAF_REMOTE=true script/runner -e test test/smoke/drb_smoke_test.rb

RECORDS_PER_PROCESS = 100000
NUM_PROCESSES       = 10
NUM_RECORDS_PER_LOGENTRY = 100

class DrbSmokeTest
  def initialize(id)
    @id = id
  end
  def self.count_connections
    res = Content.connection.execute("show status where variable_name = 'Threads_connected'")
    if res
      res.fetch_row.last
    else
      "error getting connection count"
    end
  end
  def run
    @t1 = Time.now
    RECORDS_PER_PROCESS.times do |i|
      Content.create! :title => "process #{@id}", :description => "record #{i}\n#{'Lorem ipsum. ' * 100 }"
      if i % NUM_RECORDS_PER_LOGENTRY == 0
        time = Time.now - @t1
        puts "#{@id}: #{i} records indexed, last 100 in #{time}"
        Stats.create! :process_id => @id, :records => NUM_RECORDS_PER_LOGENTRY, :processing_time => time, :open_connections => self.class.count_connections
        @t1 = Time.now
      end
    end
  end
end


#Content.delete_all

@start = Time.now

NUM_PROCESSES.times do |i|
  unless fork
    @id = i
    break
  end
end

if @id
  DrbSmokeTest.new(@id).run
else
  while true 
    puts "open connections: #{DrbSmokeTest::count_connections}; time elapsed: #{Time.now - @start} seconds"
    sleep 10 
  end
end

