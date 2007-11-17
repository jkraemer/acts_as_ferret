# Simple smoke test for the DRb server
# usage: 
#
# # start the DRb server
# script/ferret_server -e test start
#
# # run the script
# AAF_REMOTE=true script/runner -e test test/smoke/drb_smoke_test.rb

module DrbSmokeTest

  RECORDS_PER_PROCESS = 1000
  NUM_PROCESSES       = 10 # should be an even number
  NUM_RECORDS_PER_LOGENTRY = 10
  NUM_DOCS = 100
  NUM_TERMS = 1000

  TIME_FACTOR = 1000.to_f / NUM_RECORDS_PER_LOGENTRY

  class Words
    DICTIONARY = '/usr/share/dict/words'
    def initialize
      @words = []
      File.open(DICTIONARY) do |file|
        file.each_line do |word|
          @words << word.strip unless word =~ /'/
        end
      end
    end

    def to_s
      "#{@words.size} words"
    end

    def random_word
      @words[rand(@words.size)]
    end
  end

  puts "compiling sample documents..."
  WORDS = Words.new
  puts WORDS
  DOCUMENTS = []

  NUM_DOCS.times do
    doc = ''
    NUM_TERMS.times { doc << WORDS.random_word << ' ' }
    DOCUMENTS << doc
  end

  def self.random_document
    DOCUMENTS[rand(DOCUMENTS.size)]
  end

  puts "built #{NUM_DOCS} documents with an avg. size of #{DOCUMENTS.join.size / NUM_DOCS} Byte."

  class Monitor
    class << self
      def count_connections
        res = Content.connection.execute("show status where variable_name = 'Threads_connected'")
        if res
          res.fetch_row.last
        else
          "error getting connection count"
        end
      end
      def running?
        Stats.count_by_sql("select count(*) from stats where kind='finished'") < (NUM_PROCESSES/2)
      end
    end
  end

  class TestBase
    def initialize(id)
      @id = id
      @t1 = Time.now
    end

    def get_time
      returning(Time.now - @t1) do
        @t1 = Time.now
      end
    end

  end

  class Writer < TestBase
    def run
      RECORDS_PER_PROCESS.times do |i|
        Content.create! :title => "record #{@id} / #{i}", :description => DrbSmokeTest::random_document
        if i % NUM_RECORDS_PER_LOGENTRY == 0
          # write stats
          time = get_time
          puts "#{@id}: #{i} records indexed, last #{NUM_RECORDS_PER_LOGENTRY} in #{time}"
          Stats.create! :process_id => @id, :kind => 'write', :info => i, 
                        :processing_time => time * TIME_FACTOR,
                        :open_connections => Monitor::count_connections
        end
      end
      Stats.create! :process_id => @id, :kind => 'finished'
    end
  end

  class Searcher < TestBase
    def run
      while Monitor::running?
        t = Time.now
        result = Content.find_with_ferret 'findme', :lazy => true
        time = Time.now - t
        Stats.create! :process_id => @id, :kind => 'search', :info => "total_hits: #{result.total_hits} ; results: #{result.size}", 
                      :processing_time => time * 1000,
                      :open_connections => Monitor::count_connections
        sleep 1
      end
    end

  end

  def self.run
    @start = Time.now

    NUM_PROCESSES.times do |i|
      unless fork
        @id = i
        break
      end
    end

    if @id
      @id.even? ? Writer.new(@id).run : Searcher.new(@id).run
    else

      # create some records to search for
      20.times do |i|
        Content.create! :title => "to find #{i}", :description => ("findme #{i} " << random_document)
      end

      while true 
        puts "open connections: #{Monitor::count_connections}; time elapsed: #{Time.now - @start} seconds"
        sleep 10 
      end
    end
  end
end

DrbSmokeTest::run
