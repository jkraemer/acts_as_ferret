require File.dirname(__FILE__) + '/../test_helper'
require 'pp'

class ContentTest < Test::Unit::TestCase
  include Ferret::Index
  include Ferret::Search
  fixtures :contents, :comments

  def setup
    #make sure the fixtures are in the index
    ContentBase.find(:all).each { |c| c.save }
    Comment.find(:all).each { |c| c.save }

    
    @another_content = Content.new( :title => 'Another Content item', 
                                    :description => 'this is not the title' )
    @another_content.save
    @comment = @another_content.comments.create(:author => 'john doe', :content => 'This is a useless comment')
    @comment2 = @another_content.comments.create(:author => 'another', :content => 'content')
    @another_content.save # to update comment_count in ferret-index
    #puts "\n### another content: #{@another_content.id}\n"
  end
  
  def teardown
    ContentBase.find(:all).each { |c| c.destroy }
    Comment.find(:all).each { |c| c.destroy }
  end
  
  def test_truth
    assert_kind_of Content, contents(:first)
  end

  def test_unicode
    content = Content.new(:title => 'Title with some Ümläuts - äöü', 
                          :description => 'look - an ß')
    content.save
    result = Content.find_by_contents('äöü')
    assert_equal content, result.first
    result = Content.find_by_contents('üml*')
    assert_equal content, result.first
    result = Content.find_by_contents('ß')
    assert_equal content, result.first
  end

  def test_more_like_this
    assert Content.find_by_contents('lorem ipsum').empty?
    @c1 = Content.new( :title => 'Content item 1', 
                       :description => 'lorem ipsum dolor sit amet. lorem.' )
    @c1.save
    @c2 = Content.new( :title => 'Content item 2', 
                       :description => 'lorem ipsum dolor sit amet. lorem ipsum.' )
    @c2.save
    assert_equal 2, Content.find_by_contents('lorem ipsum').size
    similar = @c1.more_like_this(:field_names => ['description'], :min_doc_freq => 1, :min_term_freq => 1)
    assert_equal 1, similar.size
    assert_equal @c2, similar.first
  end

  def test_class_index_dir
    assert_equal "#{RAILS_ROOT}/index/test/content_base", Content.class_index_dir
  end

  def test_update
    contents_from_ferret = Content.find_by_contents('useless')
    assert_equal 1, contents_from_ferret.size
    assert_equal contents(:first).id, contents_from_ferret.first.id
    contents(:first).description = 'Updated description, still useless'
    contents(:first).save
    contents_from_ferret = Content.find_by_contents('useless')
    assert_equal 1, contents_from_ferret.size
    assert_equal contents(:first).id, contents_from_ferret.first.id
    contents_from_ferret = Content.find_by_contents('updated AND description')
    assert_equal 1, contents_from_ferret.size
    assert_equal contents(:first).id, contents_from_ferret.first.id
    contents_from_ferret = Content.find_by_contents('updated OR description')
    assert_equal 1, contents_from_ferret.size
    assert_equal contents(:first).id, contents_from_ferret.first.id
  end

  def test_indexed_method
    assert_equal 2, @another_content.comment_count
    assert_equal 2, contents(:first).comment_count
    assert_equal 1, contents(:another).comment_count
    # retrieve all content objects having 2 comments
    result = Content.find_by_contents('comment_count:2')
    # TODO check why this range query returns 3 results
    #result = Content.find_by_contents('comment_count:[2 TO 1000]')
    # p result
    assert_equal 2, result.size
    assert result.include?(@another_content)
    assert result.include?(contents(:first))
  end

  def test_sorting
    sorting = [ Ferret::Search::SortField.new(:id, :reverse => true) ]
    result = Content.find_by_contents('comment_count:2', :sort => sorting)
    assert result.first.id > result.last.id

    sorting = [ Ferret::Search::SortField.new(:id) ]
    result = Content.find_by_contents('comment_count:2', :sort => sorting)
    assert result.first.id < result.last.id
  end

  def test_multi_index
    i =  FerretMixin::Acts::ARFerret::MultiIndex.new([Content, Comment])
    hits = i.search(TermQuery.new(:title,"title"))
    assert_equal 1, hits.total_hits

    qp = Ferret::QueryParser.new(:default_field => "title", 
                                :analyzer => Ferret::Analysis::WhiteSpaceAnalyzer.new)
    hits = i.search(qp.parse("title"))
    assert_equal 1, hits.total_hits
    
    qp = Ferret::QueryParser.new(:fields => ['title', 'content', 'description'],
                      :analyzer => Ferret::Analysis::WhiteSpaceAnalyzer.new)
    # TODO '*' doesn't seem to work in 0.9 anymore - there's no .fields method
    # either :-(
    #qp.fields = i.reader.get_field_names.to_a
    #qp.fields = ['title','content']
    hits = i.search(qp.parse("title"))
    assert_equal 2, hits.total_hits
    hits = i.search(qp.parse("title:title OR description:title"))
    assert_equal 2, hits.total_hits

    hits = i.search("title:title OR description:title OR title:comment OR description:comment OR content:comment")
    assert_equal 5, hits.total_hits

    hits = i.search("title OR comment")
    assert_equal 5, hits.total_hits
  end

  def test_multi_searcher
    s = MultiSearcher.new([Searcher.new(Content.class_index_dir), Searcher.new(Comment.class_index_dir)])
    hits = s.search(TermQuery.new(:title,"title"))
    assert_equal 1, hits.total_hits
  end
  
  def test_multi_search
    assert_equal 4, ContentBase.find(:all).size
    
    contents_from_ferret = Content.multi_search('title:title')
    assert_equal 1, contents_from_ferret.size
    
    contents_from_ferret = Content.multi_search('title:title OR description:title')
    assert_equal 2, contents_from_ferret.size
    contents_from_ferret = Content.multi_search('*:title')
    assert_equal 2, contents_from_ferret.size
    contents_from_ferret = Content.multi_search('title')
    assert_equal 2, contents_from_ferret.size
    
    assert_equal contents(:first).id, contents_from_ferret.first.id
    assert_equal @another_content.id, contents_from_ferret.last.id
    
    contents_from_ferret = Content.multi_search('title:title OR content:comment OR description:title', [Comment])
    assert_equal 5, contents_from_ferret.size
    contents_from_ferret = Content.multi_search('*:title OR *:comment', [Comment])
    assert_equal 5, contents_from_ferret.size
    contents_from_ferret = Content.multi_search('title:(title OR comment) OR description:(title OR comment) OR content:(title OR comment)', [Comment])
    assert_equal 5, contents_from_ferret.size
  end

  def test_id_multi_search
    assert_equal 4, ContentBase.find(:all).size
    
    [ 'title:title OR description:title OR content:title', 'title', '*:title'].each do |query|
      contents_from_ferret = Content.id_multi_search(query)
      assert_equal 2, contents_from_ferret.size, query
      assert_equal contents(:first).id, contents_from_ferret.first[:id].to_i
      assert_equal @another_content.id, contents_from_ferret.last[:id].to_i
    end

    ContentBase.rebuild_index
    Comment.rebuild_index
    ['title OR comment', 'title:(title OR comment) OR description:(title OR comment) OR content:(title OR comment)'].each do |query|
      contents_from_ferret = Content.id_multi_search(query, [Comment])
      assert_equal 5, contents_from_ferret.size, query
    end
  end

  def test_find_id_by_contents
    contents_from_ferret = Content.find_id_by_contents('title:title OR description:title')
    assert_equal 2, contents_from_ferret.size
    #puts "first (id=#{contents_from_ferret.first[:id]}): #{contents_from_ferret.first[:score]}"
    #puts "last  (id=#{contents_from_ferret.last[:id]}): #{contents_from_ferret.last[:score]}"
    assert_equal contents(:first).id, contents_from_ferret.first[:id].to_i 
    assert_equal @another_content.id, contents_from_ferret.last[:id].to_i
    assert contents_from_ferret.first[:score] >= contents_from_ferret.last[:score]
     
    # give description field higher boost:
    contents_from_ferret = Content.find_id_by_contents('title:title OR description:title^10')
    assert_equal 2, contents_from_ferret.size
    #puts "first (id=#{contents_from_ferret.first[:id]}): #{contents_from_ferret.first[:score]}"
    #puts "last  (id=#{contents_from_ferret.last[:id]}): #{contents_from_ferret.last[:score]}"
    assert_equal @another_content.id, contents_from_ferret.first[:id].to_i
    assert_equal contents(:first).id, contents_from_ferret.last[:id].to_i 
    assert contents_from_ferret.first[:score] > contents_from_ferret.last[:score]
     
  end
  
  def test_find_by_contents_boost
    # give description field higher boost:
    contents_from_ferret = Content.find_by_contents('title:title OR description:title^10')
    assert_equal 2, contents_from_ferret.size
    assert_equal @another_content.id, contents_from_ferret.first.id
    assert_equal contents(:first).id, contents_from_ferret.last.id 
  end

  def test_default_and_queries
    # multiple terms are ANDed by default...
    contents_from_ferret = Content.find_by_contents('monkey description')
    assert contents_from_ferret.empty?
    # ...unless you connect them by OR
    contents_from_ferret = Content.find_by_contents('monkey OR description')
    assert_equal 1, contents_from_ferret.size
    assert_equal contents(:first).id, contents_from_ferret.first.id

    # multiple terms, each term has to occur in a document to be found, 
    # but they may occur in different fields
    contents_from_ferret = Content.find_by_contents('useless title')
    assert_equal 1, contents_from_ferret.size
    assert_equal contents(:first).id, contents_from_ferret.first.id
  end
  
  def test_find_by_contents

    contents_from_ferret = Content.find_by_contents('lorem ipsum not here')
    assert contents_from_ferret.empty?

    contents_from_ferret = Content.find_by_contents('title')
    assert_equal 2, contents_from_ferret.size
    # the title field has a higher boost value, so contents(:first) must be first in the list
    assert_equal contents(:first).id, contents_from_ferret.first.id 
    assert_equal @another_content.id, contents_from_ferret.last.id

    # find options
    contents_from_ferret = Content.find_by_contents('title', {}, :conditions => ["id=?",contents(:first).id])
    assert_equal 1, contents_from_ferret.size
    assert_equal contents(:first), contents_from_ferret.first
    
    # limit result set size to 1
    contents_from_ferret = Content.find_by_contents('title', :num_docs => 1)
    assert_equal 1, contents_from_ferret.size
    assert_equal contents(:first), contents_from_ferret.first 
    
    # limit result set size to 1, starting with the second result
    contents_from_ferret = Content.find_by_contents('title', :num_docs => 1, :first_doc => 1)
    assert_equal 1, contents_from_ferret.size
    assert_equal @another_content.id, contents_from_ferret.first.id 
     

    contents_from_ferret = Content.find_by_contents('useless')
    assert_equal 1, contents_from_ferret.size
    assert_equal contents(:first).id, contents_from_ferret.first.id
    
    # no monkeys here
    contents_from_ferret = Content.find_by_contents('monkey')
    assert contents_from_ferret.empty?
    
    

    # search for an exact string by enclosing it in "
    contents_from_ferret = Content.find_by_contents('"useless title"')
    assert contents_from_ferret.empty?
    contents_from_ferret = Content.find_by_contents('"useless description"')
    assert_equal 1, contents_from_ferret.size
    assert_equal contents(:first).id, contents_from_ferret.first.id

    # wildcard query
    contents_from_ferret = Content.find_by_contents('use*')
    assert_equal 1, contents_from_ferret.size

    # ferret-bug ? wildcard queries don't seem to get lowercased even when
    # using StandardAnalyzer:
    # contents_from_ferret = Content.find_by_contents('Ti*')
    # we should find both 'Title' and 'title'
    # assert_equal 2, contents_from_ferret.size 
    # theory: :wild_lower parser option isn't used

    contents_from_ferret = Content.find_by_contents('ti*')
    # this time we find both 'Title' and 'title'
    assert_equal 2, contents_from_ferret.size

    contents(:first).destroy
    contents_from_ferret = Content.find_by_contents('ti*')
    # should find only one now
    assert_equal 1, contents_from_ferret.size
    assert_equal @another_content.id, contents_from_ferret.first.id
   end

   def test_find_by_contents_options
     
   end
end
