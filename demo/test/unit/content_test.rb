require File.dirname(__FILE__) + '/../test_helper'
require 'pp'
require 'fileutils'

class ContentTest < Test::Unit::TestCase
  include Ferret::Index
  include Ferret::Search
  fixtures :contents, :comments

  def setup
    #make sure the fixtures are in the index
    FileUtils.rm_f 'index/test/'
    Comment.rebuild_index
    ContentBase.rebuild_index 
    raise "missing fixtures" unless ContentBase.count > 2
    
    @another_content = Content.new( :title => 'Another Content item', 
                                    :description => 'this is not the title' )
    @another_content.save
    @comment = @another_content.comments.create(:author => 'john doe', :content => 'This is a useless comment')
    @comment2 = @another_content.comments.create(:author => 'another', :content => 'content')
    @another_content.save # to update comment_count in ferret-index
  end
  
  def teardown
    ContentBase.find(:all).each { |c| c.destroy }
    Comment.find(:all).each { |c| c.destroy }
  end

  def test_include_option
    assert_equal 1, Content.find_with_ferret('description', {}, :include => :comments).size
  end

  # weiter: single index / multisearch lazy loading
  def test_lazy_loading
    results = Content.find_with_ferret 'description', :lazy => true
    assert_equal 1, results.size
    result = results.first
    assert ActsAsFerret::FerretResult === result
    assert_equal 'A useless description', result.description
    assert_nil result.instance_variable_get(:@ar_record)
    assert_equal 'My Title', result.title
    assert_not_nil result.instance_variable_get(:@ar_record)
  end

  def test_ticket_69
    content = Content.create(:title => 'aksjeselskap test',
                             :description => 'content about various norwegian companies. A.s. Haakon, Åmot Håndverksenter A/S, Øye Trelast AS')

    # these still fail: 'A\S', 'AS'
    [ '"A.s. Haakon"', 'A.s. Haakon', 'Åmot A/S', 'A/S' ].each do |query|
      assert_equal content, Content.find_with_ferret(query).first, query
    end
  end

  def test_highlight
    highlight = @another_content.highlight('title')
    assert_equal 1, highlight.size
    assert_equal "this is not the <em>title</em>", highlight.first

    highlight = @another_content.highlight('title', :field => :description)
    assert_equal 1, highlight.size
    assert_equal "this is not the <em>title</em>", highlight.first
  end

  def test_highlight_new_record
    c = Content.create :title => 'the title', :description => 'the new description'
    highlight = c.highlight('new')
    assert_equal 1, highlight.size
    assert_equal "the <em>new</em> description", highlight.first

    c1 = Content.find_with_ferret('new description').first
    assert_equal c, c1
    highlight = c1.highlight('new')
    assert_equal 1, highlight.size
    assert_equal "the <em>new</em> description", highlight.first
  end

  def test_disable_ferret_once
    content = Content.new(:title => 'should not get saved', :description => 'do not find me')
    assert_raises (ArgumentError) do
      content.disable_ferret(:wrong)
    end
    assert content.ferret_enabled?
    content.disable_ferret
    assert !content.ferret_enabled?
    content.save
    assert content.ferret_enabled?
    assert Content.find_with_ferret('"find me"').empty?

    content.save
    assert content.ferret_enabled?
    assert_equal content, Content.find_with_ferret('"find me"').first
  end

  def test_ferret_disable_always
    content = Content.new(:title => 'should not get saved', :description => 'do not find me')
    assert content.ferret_enabled?
    content.disable_ferret(:always)
    assert !content.ferret_enabled?
    2.times do 
      content.save
      assert Content.find_with_ferret('"find me"').empty?
      assert !content.ferret_enabled?
    end
    content.ferret_enable
    assert content.ferret_enabled?
    content.save
    assert content.ferret_enabled?
    assert_equal content, Content.find_with_ferret('"find me"').first
  end

  def test_disable_ferret_on_class_level
    Content.disable_ferret
    content = Content.new(:title => 'should not get saved', :description => 'do not find me')
    assert !content.ferret_enabled?
    assert !Content.ferret_enabled?
    2.times do 
      content.save
      assert Content.find_with_ferret('"find me"').empty?
      assert !Content.ferret_enabled?
      assert !content.ferret_enabled?
    end
    content.enable_ferret  # record level enabling should have no effect on class level
    assert !Content.ferret_enabled?
    assert !content.ferret_enabled?
    Content.enable_ferret
    assert Content.ferret_enabled?
    assert content.ferret_enabled?

    content.save
    assert content.ferret_enabled?
    assert Content.ferret_enabled?
    assert_equal content, Content.find_with_ferret('"find me"').first
  end

  def test_disable_ferret_block
    content = Content.new(:title => 'should not get saved', :description => 'do not find me')
    content.disable_ferret do
      2.times do
        content.save
        assert Content.find_with_ferret('"find me"').empty?
        assert !content.ferret_enabled?
      end
    end
    assert content.ferret_enabled?
    assert Content.find_with_ferret('"find me"').empty?

    content.disable_ferret(:index_when_finished) do
      2.times do
        content.save
        assert Content.find_with_ferret('"find me"').empty?
        assert !content.ferret_enabled?
      end
    end
    assert content.ferret_enabled?
    assert_equal content, Content.find_with_ferret('"find me"').first
  end

  def test_disable_ferret_on_class_level_block
    content = Content.new(:title => 'should not get saved', :description => 'do not find me')
    Content.disable_ferret do
      2.times do
        content.save
        assert Content.find_with_ferret('"find me"').empty?
        assert !content.ferret_enabled?
        assert !Content.ferret_enabled?
      end
    end
    assert content.ferret_enabled?
    assert Content.ferret_enabled?
    assert Content.find_with_ferret('"find me"').empty?
    content.save
    assert_equal content, Content.find_with_ferret('"find me"').first
  end

  # ticket 178
  def test_records_for_rebuild_works_with_includes
    size = Content.count
    Content.send( :with_scope, :find => { :include => :comments } ) do
      Content.records_for_rebuild do |records, offset|
        assert_equal size, records.size
      end
    end
  end

  def test_records_for_bulk_index
    Content.disable_ferret do
      more_contents
    end
    min = Content.find(:all, :order => 'id asc').first.id
    Content.records_for_bulk_index([min, min+1, min+2, min+3, min+4, min+6], 10) do |records, offset|
      assert_equal 6, records.size
    end
  end

  def test_bulk_index_no_optimize
    Content.disable_ferret do
      more_contents
    end

    assert Content.find_with_ferret('title').empty?
    min = Content.find(:all, :order => 'id asc').first.id
    Content.bulk_index(min, min+1, min+2, min+3, min+4, min+6, :optimize => false)
    assert_equal 6, Content.find_with_ferret('title').size
  end

  def test_bulk_index
    Content.disable_ferret do
      more_contents
    end

    assert Content.find_with_ferret('title').empty?
    min = Content.find(:all, :order => 'id asc').first.id
    Content.bulk_index([min, min+1, min+2, min+3, min+4, min+6])
    assert_equal 6, Content.find_with_ferret('title').size
  end


  def test_unicode
    content = Content.new(:title => 'Title with some Ümläuts - äöü', 
                          :description => 'look - an ß')
    content.save
    result = Content.find_with_ferret('äöü')
    assert_equal content, result.first
    result = Content.find_with_ferret('üml*')
    assert_equal content, result.first
    result = Content.find_with_ferret('ß')
    assert_equal content, result.first
  end

  def test_content_for_field_name
    c = 'lorem ipsum dolor sit amet. lorem.'
    @c1 = Content.new( :title => 'Content item 1', 
                       :description => c )
    assert_equal c, @c1.content_for_field_name(:description)
  end

  def test_document_number
    c = 'lorem ipsum dolor sit amet. lorem.'
    c1 = Content.new( :title => 'Content item 1', 
                       :description => c )
    c1.save
    fi = Content.aaf_index.ferret_index
    hits = fi.search('title:"Content item 1"')
    assert_equal 1, hits.total_hits
    expected_doc_num = hits.hits.first.doc
    assert_equal c, fi[expected_doc_num][:description]
    doc_num = c1.document_number
    assert_equal expected_doc_num, doc_num
    assert_equal c, fi[doc_num][:description]
  end

  def test_more_like_this
    assert Content.find_with_ferret('lorem ipsum').empty?
    @c1 = Content.new( :title => 'Content item 1', 
                       :description => 'lorem ipsum dolor sit amet. lorem.' )
    @c1.save
    @c2 = Content.new( :title => 'Content item 2', 
                       :description => 'lorem ipsum dolor sit amet. lorem ipsum.' )
    @c2.save
    assert_equal 2, Content.find_with_ferret('lorem ipsum').size
    similar = @c1.more_like_this(:field_names => [:description], :min_doc_freq => 1, :min_term_freq => 1)
    assert_equal 1, similar.size
    assert_equal @c2, similar.first
  end

  def test_more_like_this_new_record
    assert Content.find_with_ferret('lorem ipsum').empty?
    @c1 = Content.new( :title => 'Content item 1', 
                       :description => 'lorem ipsum dolor sit amet. lorem.' )
    @c2 = Content.new( :title => 'Content item 2', 
                       :description => 'lorem ipsum dolor sit amet. lorem ipsum.' )
    @c2.save
    assert_equal 1, Content.find_with_ferret('lorem ipsum').size
    similar = @c1.more_like_this(:field_names => [:description], :min_doc_freq => 1, :min_term_freq => 1)
    assert_equal 1, similar.size
    assert_equal @c2, similar.first
  end

  def test_class_index_dir
    assert Content.aaf_configuration[:index_dir] =~ %r{^#{RAILS_ROOT}/index/test/content_base}
  end
  
  def test_update
    contents_from_ferret = Content.find_with_ferret('useless')
    assert_equal 1, contents_from_ferret.size
    assert_equal contents(:first).id, contents_from_ferret.first.id
    contents(:first).description = 'Updated description, still useless'
    contents(:first).save
    contents_from_ferret = Content.find_with_ferret('useless')
    assert_equal 1, contents_from_ferret.size
    assert_equal contents(:first).id, contents_from_ferret.first.id
    contents_from_ferret = Content.find_with_ferret('updated AND description')
    assert_equal 1, contents_from_ferret.size
    assert_equal contents(:first).id, contents_from_ferret.first.id
    contents_from_ferret = Content.find_with_ferret('updated OR description')
    assert_equal 1, contents_from_ferret.size
    assert_equal contents(:first).id, contents_from_ferret.first.id
  end

  def test_indexed_method
    assert_equal 2, @another_content.comment_count
    assert_equal 2, contents(:first).comment_count
    assert_equal 1, contents(:another).comment_count
    # retrieve all content objects having 2 comments
    result = Content.find_with_ferret('comment_count:2')
    # TODO check why this range query returns 3 results
    #result = Content.find_with_ferret('comment_count:[2 TO 1000]')
    # p result
    assert_equal 2, result.size
    assert result.include?(@another_content)
    assert result.include?(contents(:first))
  end

  def test_sorting
    sorting = [ Ferret::Search::SortField.new(:id, :reverse => true) ]
    result = Content.find_with_ferret('comment_count:2', :sort => sorting)
    assert result.first.id > result.last.id

    sorting = [ Ferret::Search::SortField.new(:id) ]
    result = Content.find_with_ferret('comment_count:2', :sort => sorting)
    assert result.first.id < result.last.id

    sorting = Ferret::Search::Sort.new([ Ferret::Search::SortField.new(:id), 
                                         Ferret::Search::SortField::SCORE ],
                                        :reverse => true)


    result = Content.find_with_ferret('comment_count:2', :sort => sorting)
    assert result.first.id > result.last.id
  end
  
  def test_total_hits_multi
    result = Content.total_hits('*:title OR *:comment', :multi => Comment)
    assert_equal 5, result
  end

  def test_multi_search_sorting
    sorting = [ Ferret::Search::SortField.new(:id) ]
    result = Content.find_with_ferret('*:title OR *:comment', :multi => [Comment], :sort => sorting)
    assert_equal result.map(&:id).sort, result.map(&:id)

    sorting = [ Ferret::Search::SortField.new(:title) ]
    result = Content.find_with_ferret('*:title OR *:comment', :multi => [Comment], :sort => sorting)
    sorting = [ Ferret::Search::SortField.new(:title, :reverse => true) ]
    result2 = Content.find_with_ferret('*:title OR *:comment', :multi => [Comment], :sort => sorting)
    assert result.any?
    assert result.map(&:id) != result2.map(&:id)

    sorting = [ Ferret::Search::SortField::SCORE ]
    result = Content.find_with_ferret('*:title OR *:comment', :multi => Comment, :sort => sorting)
    assert result.any?
    assert_equal result.map(&:ferret_score).sort.reverse, result.map(&:ferret_score)

    sorting = [ Ferret::Search::SortField::SCORE_REV ]
    result2 = Content.find_with_ferret('*:title OR *:comment', :multi => Comment, :sort => sorting)
    assert_equal result2.map(&:ferret_score).sort, result2.map(&:ferret_score)
    assert_equal result.map(&:ferret_score), result2.map(&:ferret_score).reverse
  end

  def test_sort_class
    sorting = Ferret::Search::Sort.new(Ferret::Search::SortField.new(:id, :reverse => true))
    result = Content.find_with_ferret('comment_count:2 OR comment_count:1', :sort => sorting)
    assert result.size > 2
    assert result.first.id > result.last.id
    result = Content.find_with_ferret('comment_count:2 OR comment_count:1', :sort => sorting, :limit => 2)
    assert_equal 2, result.size
    assert result.first.id > result.last.id
  end
  
  def test_sort_with_limit
    sorting = [ Ferret::Search::SortField.new(:id) ]
    result = Content.find_with_ferret('comment_count:2 OR comment_count:1', :sort => sorting)
    assert result.size > 2
    assert result.first.id < result.last.id
    result = Content.find_with_ferret('comment_count:2 OR comment_count:1', :sort => sorting, :limit => 2)
    assert_equal 2, result.size
    assert result.first.id < result.last.id

    sorting = [ Ferret::Search::SortField.new(:id, :reverse => true) ]
    result = Content.find_with_ferret('comment_count:2 OR comment_count:1', :sort => sorting)
    assert result.size > 2
    assert result.first.id > result.last.id
    result = Content.find_with_ferret('comment_count:2 OR comment_count:1', :sort => sorting, :limit => 2)
    assert_equal 2, result.size
    assert result.first.id > result.last.id
  end
  
  # remote index rebuilds will create an index in a directory with a timestamped name.
  # the local MultiIndex instance doesn't know about this (because it's running in 
  # another interpreter instance than the server) and therefore fails to use the 
  # correct index directories.
  # TODO strange, still doesn't work but it should now...
  unless Content.aaf_configuration[:remote]
    def test_multi_index
      i =  ActsAsFerret::MultiIndex.new([Content, Comment])
      hits = i.search(TermQuery.new(:title,"title"))
      assert_equal 1, hits.total_hits

      qp = Ferret::QueryParser.new(:default_field => "title", 
                                  :analyzer => Ferret::Analysis::WhiteSpaceAnalyzer.new)
      hits = i.search(qp.parse("title"))
      assert_equal 1, hits.total_hits
      
      qp = Ferret::QueryParser.new(:fields => ['title', 'content', 'description'],
                        :analyzer => Ferret::Analysis::WhiteSpaceAnalyzer.new)
      hits = i.search(qp.parse("title"))
      assert_equal 2, hits.total_hits
      hits = i.search(qp.parse("title:title OR description:title"))
      assert_equal 2, hits.total_hits

      hits = i.search("title:title OR description:title OR title:comment OR description:comment OR content:comment")
      assert_equal 5, hits.total_hits

      hits = i.search("title OR comment")
      assert_equal 5, hits.total_hits

      hits = i.search("title OR comment", :limit => 2)
      count = 0
      hits.hits.each { |hit, score| count += 1 }
      assert_equal 2, count

      hits = i.search("title OR comment", :offset => 2)
      count = 0
      hits.hits.each { |hit, score| count += 1 }
      assert_equal 3, count
    end
  end

  def test_add_rebuilds_index
    remove_index Content
    Content.create(:title => 'another one', :description => 'description')
    contents_from_ferret = Content.find_with_ferret('description:title')
    assert_equal 1, contents_from_ferret.size
  end
  def test_find_rebuilds_index
    remove_index Content
    contents_from_ferret = Content.find_with_ferret('description:title')
    assert_equal 1, contents_from_ferret.size
  end

  def test_multi_search_rebuilds_index
    remove_index Content
    contents_from_ferret = Content.find_with_ferret('description:title', :multi => Comment)
    assert_equal 1, contents_from_ferret.size
  end

  # remote index rebuilds will create an index in a directory with a timestamped name...
  unless Content.aaf_configuration[:remote]
    def test_multi_index_rebuilds_index
      remove_index Content
      i =  ActsAsFerret::MultiIndex.new([Content])
      assert File.exists?("#{Content.aaf_configuration[:index_dir]}/segments")
      hits = i.search("description:title")
      assert_equal 1, hits.total_hits, hits.inspect
    end
  end

  def test_multi_search_find_options
    contents_from_ferret = Content.find_with_ferret('title', { :multi => Comment }, :order => 'id desc')
    assert_equal 2, contents_from_ferret.size
    assert contents_from_ferret.first.id > contents_from_ferret.last.id
    contents_from_ferret = Content.find_with_ferret('title', { :multi => Comment }, :order => 'id asc')
    assert contents_from_ferret.first.id < contents_from_ferret.last.id

    contents_from_ferret = Content.find_with_ferret('title', { :multi => Comment }, :limit => 1)
    assert_equal 1, contents_from_ferret.size
  end

  def test_multi_search
    assert_equal 4, ContentBase.find(:all).size
    
    Content.aaf_index.ferret_index.flush
    contents_from_ferret = Content.multi_search('description:title')
    assert_equal 1, contents_from_ferret.size
    contents_from_ferret = Content.multi_search('title:title OR description:title')
    assert_equal 2, contents_from_ferret.size
    contents_from_ferret = Content.multi_search('title:title')
    assert_equal 1, contents_from_ferret.size
    contents_from_ferret = Content.multi_search('*:title')
    assert_equal 2, contents_from_ferret.size
    contents_from_ferret = Content.multi_search('title')
    assert_equal 2, contents_from_ferret.size
    
    assert_equal contents(:first).id, contents_from_ferret.first.id
    assert_equal @another_content.id, contents_from_ferret.last.id
    
    contents_from_ferret = Content.multi_search('title', [])
    assert_equal 2, contents_from_ferret.size
    contents_from_ferret = Content.multi_search('title', [], :limit => 1)
    assert_equal 1, contents_from_ferret.size
    contents_from_ferret = Content.multi_search('title', [], :offset => 1)
    assert_equal 1, contents_from_ferret.size

    contents_from_ferret = Content.multi_search('title:title OR content:comment OR description:title', [Comment])
    assert_equal 5, contents_from_ferret.size
    contents_from_ferret = Content.multi_search('title:title OR content:comment OR description:title', [Comment], :limit => 2)
    assert_equal 2, contents_from_ferret.size

    contents_from_ferret = Content.multi_search('*:title OR *:comment', Comment)
    assert_equal 5, contents_from_ferret.size
    contents_from_ferret = Content.multi_search('*:title OR *:comment', [Comment])
    assert_equal 5, contents_from_ferret.size
    contents_from_ferret = Content.multi_search('title:(title OR comment) OR description:(title OR comment) OR content:(title OR comment)', [Comment])
    assert_equal 5, contents_from_ferret.size
  end

  def test_multi_search_lazy
    contents_from_ferret = Content.find_with_ferret('title', :multi => Comment, :lazy => true)
    assert_equal 2, contents_from_ferret.size
    contents_from_ferret.each do |record|
      assert ActsAsFerret::FerretResult === record, record.inspect
      assert !record.description.blank?
      assert_nil record.instance_variable_get(:"@ar_record")
    end
  end

  def test_id_multi_search
    assert_equal 4, ContentBase.find(:all).size
    
    [ 'title:title OR description:title OR content:title', 'title', '*:title'].each do |query|
      total_hits, contents_from_ferret = Content.id_multi_search(query)
      assert_equal 2, contents_from_ferret.size, query
      assert_equal 2, total_hits, query
      assert_equal contents(:first).id, contents_from_ferret.first[:id].to_i
      assert_equal @another_content.id, contents_from_ferret.last[:id].to_i
    end

    ContentBase.rebuild_index
    Comment.rebuild_index
    ['title OR comment', 'title:(title OR comment) OR description:(title OR comment) OR content:(title OR comment)'].each do |query|
      total_hits, contents_from_ferret = Content.id_multi_search(query, [Comment])
      assert_equal 5, contents_from_ferret.size, query
      assert_equal 5, total_hits
    end
  end

  def test_id_multi_search_lazy
    total_hits, contents_from_ferret = Content.id_multi_search('title', [Comment], :lazy => true)
    assert_equal 2, contents_from_ferret.size
    assert_equal 2, total_hits
    found = 0
    contents_from_ferret.each do |data|
      next if data[:model] != 'Content'
      found += 1
      assert !data[:data][:description].blank?
    end
    assert_equal 2, found
  end

  def test_total_hits
    assert_equal 2, Content.total_hits('title:title OR description:title')
    assert_equal 2, Content.total_hits('title:title OR description:title', :limit => 1)
  end

  def test_find_id_by_contents
    total_hits, contents_from_ferret = Content.find_id_by_contents('title:title OR description:title')
    assert_equal 2, contents_from_ferret.size
    assert_equal 2, total_hits
    #puts "first (id=#{contents_from_ferret.first[:id]}): #{contents_from_ferret.first[:score]}"
    #puts "last  (id=#{contents_from_ferret.last[:id]}): #{contents_from_ferret.last[:score]}"
    assert_equal contents(:first).id, contents_from_ferret.first[:id].to_i 
    assert_equal @another_content.id, contents_from_ferret.last[:id].to_i
    assert contents_from_ferret.first[:score] >= contents_from_ferret.last[:score]
     
    # give description field higher boost:
    total_hits, contents_from_ferret = Content.find_id_by_contents('title:title OR description:title^200')
    assert_equal 2, contents_from_ferret.size
    assert_equal 2, total_hits
    #puts "first (id=#{contents_from_ferret.first[:id]}): #{contents_from_ferret.first[:score]}"
    #puts "last  (id=#{contents_from_ferret.last[:id]}): #{contents_from_ferret.last[:score]}"
    assert_equal @another_content.id, contents_from_ferret.first[:id].to_i
    assert_equal contents(:first).id, contents_from_ferret.last[:id].to_i 
    assert contents_from_ferret.first[:score] > contents_from_ferret.last[:score]
     
  end
  
  def test_find_with_ferret_boost
    # give description field higher boost:
    contents_from_ferret = Content.find_with_ferret('title:title OR description:title^200')
    assert_equal 2, contents_from_ferret.size
    assert_equal @another_content.id, contents_from_ferret.first.id
    assert_equal contents(:first).id, contents_from_ferret.last.id 
  end

  def test_default_and_queries
    # multiple terms are ANDed by default...
    contents_from_ferret = Content.find_with_ferret('monkey description')
    assert contents_from_ferret.empty?
    # ...unless you connect them by OR
    contents_from_ferret = Content.find_with_ferret('monkey OR description')
    assert_equal 1, contents_from_ferret.size
    assert_equal contents(:first).id, contents_from_ferret.first.id

    # multiple terms, each term has to occur in a document to be found, 
    # but they may occur in different fields
    contents_from_ferret = Content.find_with_ferret('useless title')
    assert_equal 1, contents_from_ferret.size
    assert_equal contents(:first).id, contents_from_ferret.first.id
  end
  
  def test_find_with_ferret

    contents_from_ferret = Content.find_with_ferret('lorem ipsum not here')
    assert contents_from_ferret.empty?

    contents_from_ferret = Content.find_with_ferret('title')
    assert_equal 2, contents_from_ferret.size
    # the title field has a higher boost value, so contents(:first) must be first in the list
    assert_equal contents(:first).id, contents_from_ferret.first.id 
    assert_equal @another_content.id, contents_from_ferret.last.id

     

    contents_from_ferret = Content.find_with_ferret('useless')
    assert_equal 1, contents_from_ferret.size
    assert_equal contents(:first).id, contents_from_ferret.first.id
    
    # no monkeys here
    contents_from_ferret = Content.find_with_ferret('monkey')
    assert contents_from_ferret.empty?
    
    

    # search for an exact string by enclosing it in "
    contents_from_ferret = Content.find_with_ferret('"useless title"')
    assert contents_from_ferret.empty?
    contents_from_ferret = Content.find_with_ferret('"useless description"')
    assert_equal 1, contents_from_ferret.size
    assert_equal contents(:first).id, contents_from_ferret.first.id

    # wildcard query
    contents_from_ferret = Content.find_with_ferret('use*')
    assert_equal 1, contents_from_ferret.size

    # ferret-bug ? wildcard queries don't seem to get lowercased even when
    # using StandardAnalyzer:
    # contents_from_ferret = Content.find_with_ferret('Ti*')
    # we should find both 'Title' and 'title'
    # assert_equal 2, contents_from_ferret.size 
    # theory: :wild_lower parser option isn't used

    contents_from_ferret = Content.find_with_ferret('ti*')
    # this time we find both 'Title' and 'title'
    assert_equal 2, contents_from_ferret.size

    contents(:first).destroy
    contents_from_ferret = Content.find_with_ferret('ti*')
    # should find only one now
    assert_equal 1, contents_from_ferret.size
    assert_equal @another_content.id, contents_from_ferret.first.id
  end

  def test_find_with_ferret_options
    # find options
    contents_from_ferret = Content.find_with_ferret('title', {}, :conditions => ["id=?",contents(:first).id])
    assert_equal 1, contents_from_ferret.size
    assert_equal contents(:first), contents_from_ferret.first
    
    # limit result set size to 1
    contents_from_ferret = Content.find_with_ferret('title', :limit => 1)
    assert_equal 1, contents_from_ferret.size
    assert_equal contents(:first), contents_from_ferret.first 
    
    # limit result set size to 1, starting with the second result
    contents_from_ferret = Content.find_with_ferret('title', :limit => 1, :offset => 1)
    assert_equal 1, contents_from_ferret.size
    assert_equal @another_content.id, contents_from_ferret.first.id 

    # deprecated options, still supported
    contents_from_ferret = Content.find_with_ferret('title', :num_docs => 1, :first_doc => 1)
    assert_equal 1, contents_from_ferret.size
    assert_equal @another_content.id, contents_from_ferret.first.id 
     
  end

  def test_multi_pagination
    more_contents(true)

    r = Content.find_with_ferret 'title OR comment', :multi => Comment, :per_page => 10, :sort => 'title'
    assert_equal 60, r.total_hits
    assert_equal 10, r.size
    assert_equal "0", r.first.description
    assert_equal "9", r.last.description
    assert_equal 1, r.current_page
    assert_equal 6, r.page_count

    r = Content.find_with_ferret 'title OR comment', :multi => Comment, :page => '2', :per_page => 10, :sort => 'title'
    assert_equal 60, r.total_hits
    assert_equal 10, r.size
    assert_equal "10", r.first.description
    assert_equal "19", r.last.description
    assert_equal 2, r.current_page
    assert_equal 6, r.page_count

    r = Content.find_with_ferret 'title OR comment', :multi => Comment, :page => 7, :per_page => 10, :sort => 'title'
    assert_equal 60, r.total_hits
    assert_equal 0, r.size
  end

  def test_pagination
    more_contents

    r = Content.find_with_ferret 'title', :per_page => 10, :sort => 'title'
    assert_equal 30, r.total_hits
    assert_equal 10, r.size
    assert_equal "0", r.first.description
    assert_equal "9", r.last.description
    assert_equal 1, r.current_page
    assert_equal 3, r.page_count

    r = Content.find_with_ferret 'title', :page => '2', :per_page => 10, :sort => 'title'
    assert_equal 30, r.total_hits
    assert_equal 10, r.size
    assert_equal "10", r.first.description
    assert_equal "19", r.last.description
    assert_equal 2, r.current_page
    assert_equal 3, r.page_count

    r = Content.find_with_ferret 'title', :page => 4, :per_page => 10, :sort => 'title'
    assert_equal 30, r.total_hits
    assert_equal 0, r.size
  end

  def test_pagination_with_ar_conditions
    more_contents

    r = Content.find_with_ferret 'title', { :page => 1, :per_page => 10 }, 
                                          { :conditions => "description != '0'", :order => 'title ASC' }
    assert_equal 29, r.total_hits
    assert_equal 10, r.size
    assert_equal "1", r.first.description
    assert_equal "10", r.last.description
    assert_equal 1, r.current_page
    assert_equal 3, r.page_count

    r = Content.find_with_ferret 'title', { :page => 3, :per_page => 10 },
                                          { :conditions => "description != '0'", :order => 'title ASC' }
    assert_equal 29, r.total_hits
    assert_equal 9, r.size
    assert_equal "21", r.first.description
    assert_equal "29", r.last.description
    assert_equal 3, r.current_page
    assert_equal 3, r.page_count
  end

  def test_multi_pagination_with_ar_conditions
    more_contents(true)
    id = Content.find_with_ferret('title').first.id
    r = Content.find_with_ferret 'title OR comment', { :page => 1, :per_page => 10, :multi => Comment }, 
                                          { :conditions => ["id != ?", id], :order => 'id ASC' }
    assert_equal 59, r.total_hits
    assert_equal 10, r.size
    assert_equal "Comment for content 00", r.first.content
    assert_equal "Comment for content 09", r.last.content
    assert_equal 1, r.current_page
    assert_equal 6, r.page_count

    r = Content.find_with_ferret 'title OR comment', { :page => 6, :per_page => 10, :multi => Comment },
                                          { :conditions => [ "id != ?", id ], :order => 'id ASC' }
    assert_equal 59, r.total_hits
    assert_equal 9, r.size
    assert_equal "21", r.first.description
    assert_equal "29", r.last.description
    assert_equal 6, r.current_page
    assert_equal 6, r.page_count
  end

  def test_pagination_with_more_conditions
    more_contents

    r = Content.find_with_ferret 'title -description:0', { :page => 1, :per_page => 10 },
                                            { :conditions => "contents.description != '9'", :order => 'title ASC' }
    assert_equal 28, r.total_hits
    assert_equal 10, r.size
    assert_equal "1", r.first.description
    assert_equal "11", r.last.description
    assert_equal 1, r.current_page
    assert_equal 3, r.page_count
  end

  def test_reconnect_in_drb_mode
    if ENV['AAF_REMOTE'] && Content.connection.is_a?(ActiveRecord::ConnectionAdapters::MysqlAdapter)
      puts "have DRb and MySQL - doing db reconnect test"
      Content.aaf_index.send(:db_disconnect!)
      c = Content.create! :title => 'another one', :description => 'description'
      assert_equal c, Content.find_with_ferret('another').first
    else
      assert true
    end
  end

  def test_per_field_boost
    Content.destroy_all
    Content.create! :title => 'the title'
    boosted = Content.new :title => 'the title'
    boosted.title_boost = 100
    boosted.save!
    Content.create! :title => 'the title'
    results = Content.find_with_ferret 'title:title'
    assert_equal 3, results.size
    assert_equal boosted.id, results.first.id
  end

  def test_per_document_boost
    Content.destroy_all
    Content.create! :title => 'the title'
    boosted = Content.new :title => 'the title'
    boosted.record_boost = 10
    boosted.save!
    Content.create! :title => 'the title'
    results = Content.find_with_ferret 'title'
    assert_equal 3, results.size
    assert_equal boosted.id, results.first.id
  end


  protected

  def more_contents(with_comments = false)
    Comment.destroy_all if with_comments
    Content.destroy_all
    SpecialContent.destroy_all
    30.times do |i|
      c = Content.create! :title => sprintf("title of Content %02d", i), :description => "#{i}"
      c.comments.create! :content => sprintf("Comment for content %02d", i) if with_comments
    end
  end

  def remove_index(clazz)
    clazz.aaf_index.close # avoid io error when deleting the open index
    FileUtils.rm_rf clazz.aaf_configuration[:index_dir]
    assert !File.exists?("#{clazz.aaf_configuration[:index_dir]}/segments")
  end

end
