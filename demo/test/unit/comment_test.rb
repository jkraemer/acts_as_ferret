require File.dirname(__FILE__) + '/../test_helper'

class CommentTest < Test::Unit::TestCase
  fixtures :comments

  def setup
    Comment.rebuild_index
  end

  # Replace this with your real tests.
  def test_truth
    assert_kind_of Comment, comments(:first)
  end

  def test_class_index_dir
    assert Comment.aaf_configuration[:index_dir] =~ %r{^#{RAILS_ROOT}/index/test/comment}
  end

  def test_search_for_id
    # don't search the id field by default:
    assert Comment.find_by_contents('3').empty?
    # explicit query for id field works:
    assert_equal 3, Comment.find_by_contents('id:3').first.id
  end

  #def test_reloadable
  #  assert ! Comment.reloadable?
  #end

  # tests the automatic building of an index when none exists
  # delete index/test/* before running rake to make this useful
  def test_automatic_index_build
    # TODO: check why this fails, but querying for 'comment fixture' works.
    # maybe different analyzers at index creation and searching time ?
    #comments_from_ferret = Comment.find_by_contents('"comment from fixture"')
    comments_from_ferret = Comment.find_by_contents('comment fixture')
    assert_equal 2, comments_from_ferret.size
    assert comments_from_ferret.include?(comments(:first))
    assert comments_from_ferret.include?(comments(:another))
  end

  def test_rebuild_index
    Comment.aaf_index.ferret_index.query_delete('comment')
    comments_from_ferret = Comment.find_by_contents('comment AND fixture')
    assert comments_from_ferret.empty?
    Comment.rebuild_index
    comments_from_ferret = Comment.find_by_contents('comment AND fixture')
    assert_equal 2, comments_from_ferret.size
  end

  def test_total_hits
    comments_from_ferret = Comment.find_by_contents('comment AND fixture', :limit => 1)
    assert_equal 1, comments_from_ferret.size
    assert_equal 2, comments_from_ferret.total_hits

    comments_from_ferret = Comment.find_by_contents('comment AND fixture', {}, :conditions => 'id != 1')
    assert_equal 1, comments_from_ferret.size
    assert_equal 1, comments_from_ferret.total_hits
  end

  def test_score
    comments_from_ferret = Comment.find_by_contents('comment AND fixture', :limit => 1)
    assert comments_from_ferret.first
    assert comments_from_ferret.first.ferret_score > 0
  end

  def test_find_all
    20.times do |i|
      Comment.create( :author => 'multi-commenter', :content => "This is multicomment no #{i}" )
    end
    assert_equal 10, (res = Comment.find_by_contents('multicomment')).size
    assert_equal 20, res.total_hits
    assert_equal 15, (res = Comment.find_by_contents('multicomment', :limit => 15)).size
    assert_equal 20, res.total_hits
    assert_equal 20, (res = Comment.find_by_contents('multicomment', :limit => :all)).size
    assert_equal 20, res.total_hits
  end

  # tests the custom to_doc method defined in comment.rb
  def test_custom_to_doc
    top_docs = Comment.aaf_index.ferret_index.search('"from fixture"')
    #top_docs = Comment.ferret_index.search('"comment from fixture"')
    assert_equal 2, top_docs.total_hits
    doc = Comment.aaf_index.ferret_index.doc(top_docs.hits[0].doc)
    # check for the special field added by the custom to_doc method
    assert_not_nil doc[:added]
    # still a valid int ?
    assert doc[:added].to_i > 0
  end

  def test_find_by_contents
    comment = Comment.create( :author => 'john doe', :content => 'This is a useless comment' )
    comment2 = Comment.create( :author => 'another', :content => 'content' )

    comments_from_ferret = Comment.find_by_contents('anoth* OR jo*')
    assert_equal 2, comments_from_ferret.size
    assert comments_from_ferret.include?(comment)
    assert comments_from_ferret.include?(comment2)
    
    # find options
    comments_from_ferret = Comment.find_by_contents('anoth* OR jo*', {}, :conditions => ["id=?",comment2.id])
    assert_equal 1, comments_from_ferret.size
    assert comments_from_ferret.include?(comment2)
    
    comments_from_ferret = Comment.find_by_contents('lorem ipsum not here')
    assert comments_from_ferret.empty?

    comments_from_ferret = Comment.find_by_contents('another')
    assert_equal 1, comments_from_ferret.size
    assert_equal comment2.id, comments_from_ferret.first.id
    
    comments_from_ferret = Comment.find_by_contents('doe')
    assert_equal 1, comments_from_ferret.size
    assert_equal comment.id, comments_from_ferret.first.id
    
    comments_from_ferret = Comment.find_by_contents('useless')
    assert_equal 1, comments_from_ferret.size
    assert_equal comment.id, comments_from_ferret.first.id
  
    # no monkeys here
    comments_from_ferret = Comment.find_by_contents('monkey')
    assert comments_from_ferret.empty?
    
    # multiple terms are ANDed by default...
    comments_from_ferret = Comment.find_by_contents('monkey comment')
    assert comments_from_ferret.empty?
    # ...unless you connect them by OR
    comments_from_ferret = Comment.find_by_contents('monkey OR comment')
    assert_equal 3, comments_from_ferret.size
    assert comments_from_ferret.include?(comment)
    assert comments_from_ferret.include?(comments(:first))
    assert comments_from_ferret.include?(comments(:another))

    # multiple terms, each term has to occur in a document to be found, 
    # but they may occur in different fields
    comments_from_ferret = Comment.find_by_contents('useless john')
    assert_equal 1, comments_from_ferret.size
    assert_equal comment.id, comments_from_ferret.first.id
    

    # search for an exact string by enclosing it in "
    comments_from_ferret = Comment.find_by_contents('"useless john"')
    assert comments_from_ferret.empty?
    comments_from_ferret = Comment.find_by_contents('"useless comment"')
    assert_equal 1, comments_from_ferret.size
    assert_equal comment.id, comments_from_ferret.first.id

    comment.destroy
    comment2.destroy
  end

  # fixed with Ferret 0.9.6
  def test_stopwords_ferret_bug 
    i = Ferret::I.new(:or_default => false, :default_field => '*' )
    d = Ferret::Document.new
    d[:id] = '1'
    d[:content] = 'Move or shake'
    i << d
    hits = i.search 'move AND or AND shake'
    assert_equal 1, hits.total_hits
    hits = i.search 'move AND nothere AND shake'
    assert_equal 0, hits.total_hits
    hits = i.search 'move AND shake'
    assert_equal 1, hits.total_hits
    hits = i.search 'move OR shake'
    assert_equal 1, hits.total_hits
    hits = i.search '+move +the +shake'
    assert_equal 1, hits.total_hits

    hits = i.search 'move nothere'
    assert_equal 0, hits.total_hits
  end

  def test_stopwords
    comment = Comment.create( :author => 'john doe', :content => 'Move or shake' )
    ['move shake', 'Move shake', 'move Shake', 'move or shake', 'move the shake'].each do |q|
      comments_from_ferret = Comment.find_by_contents(q)
      assert_equal comment, comments_from_ferret.first, "query #{q} failed"
    end
    comment.destroy
  end

  def test_array_conditions_combining 
    comments_from_ferret = Comment.find_by_contents('comment AND fixture', {}, :conditions => [ 'id IN (?)', [ 2, 3 ] ]) 
    assert_equal 1, comments_from_ferret.size 
    assert_equal 1, comments_from_ferret.total_hits 
  end

  def test_pagination
    more_contents

    r = Content.find_with_ferret 'title', :page => 1, :per_page => 10, :sort => 'title'
    assert_equal 30, r.total_hits
    assert_equal 10, r.size
    assert_equal "0", r.first.description
    assert_equal "9", r.last.description
    assert_equal 1, r.current_page
    assert_equal 3, r.page_count

    r = Content.find_with_ferret 'title', :page => 2, :per_page => 10, :sort => 'title'
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

  protected
  def more_contents
    Content.destroy_all
    30.times do |i|
      Content.create! :title => sprintf("title of Content %02d", i), :description => "#{i}"
    end
  end

end
