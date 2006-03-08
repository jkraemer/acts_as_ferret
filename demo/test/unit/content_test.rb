require File.dirname(__FILE__) + '/../test_helper'

class ContentTest < Test::Unit::TestCase
  fixtures :contents

  def test_truth
    assert_kind_of Content, contents(:first)
  end

  def test_class_index_dir
    assert_equal "#{RAILS_ROOT}/index/test/Content", Content.class_index_dir
  end

  def test_find_by_contents
    @content = Content.new( :title => 'My Title', :description => 'A useless description' )
    @content.save
    @another_content = Content.new( :title => 'Another Content item', 
                                    :description => 'this is not the title' )
    @another_content.save

    contents_from_ferret = Content.find_by_contents('title')
    assert_equal 2, contents_from_ferret.size
    # the title field has a higher boost value, so @content must be first in the list
    assert_equal @content.id, contents_from_ferret.first.id 
    assert_equal @another_content.id, contents_from_ferret.last.id
    
    # limit result set size to 1
    contents_from_ferret = Content.find_by_contents('title', :num_docs => 1)
    assert_equal 1, contents_from_ferret.size
    assert_equal @content.id, contents_from_ferret.first.id 
    
    # limit result set size to 1, starting with the second result
    contents_from_ferret = Content.find_by_contents('title', :num_docs => 1, :first_doc => 1)
    assert_equal 1, contents_from_ferret.size
    assert_equal @another_content.id, contents_from_ferret.first.id 
     

    contents_from_ferret = Content.find_by_contents('useless')
    assert_equal 1, contents_from_ferret.size
    assert_equal @content.id, contents_from_ferret.first.id
    
    # no monkeys here
    contents_from_ferret = Content.find_by_contents('monkey')
    assert contents_from_ferret.empty?
    
    # multiple terms are ANDed by default...
    contents_from_ferret = Content.find_by_contents('monkey description')
    assert contents_from_ferret.empty?
    # ...unless you connect them by OR
    contents_from_ferret = Content.find_by_contents('monkey OR description')
    assert_equal 1, contents_from_ferret.size
    assert_equal @content.id, contents_from_ferret.first.id

    # multiple terms, each term has to occur in a document to be found, 
    # but they may occur in different fields
    contents_from_ferret = Content.find_by_contents('useless title')
    assert_equal 1, contents_from_ferret.size
    assert_equal @content.id, contents_from_ferret.first.id
    

    # search for an exact string by enclosing it in "
    contents_from_ferret = Content.find_by_contents('"useless title"')
    assert contents_from_ferret.empty?
    contents_from_ferret = Content.find_by_contents('"useless description"')
    assert_equal 1, contents_from_ferret.size
    assert_equal @content.id, contents_from_ferret.first.id

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
    
   end

   def test_find_by_contents_options
     
   end
end
