require File.dirname(__FILE__) + '/../test_helper'

class CommentTest < Test::Unit::TestCase
  fixtures :comments

  # Replace this with your real tests.
  def test_truth
    assert_kind_of Comment, comments(:first)
  end

  def test_class_index_dir
    assert_equal "#{RAILS_ROOT}/index/test/Comment", Comment.class_index_dir
  end

  def test_find_by_contents
    comment = Comment.new( :author => 'john doe', :content => 'This is a useless comment' )
    comment.save

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
    assert_equal 1, comments_from_ferret.size
    assert_equal comment.id, comments_from_ferret.first.id

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
   end

end
