require File.dirname(__FILE__) + '/../test_helper'

class SpecialContentTest < Test::Unit::TestCase
  include Ferret::Index
  include Ferret::Search
  fixtures :contents, :comments

  def setup
    Content.rebuild_index
    Comment.rebuild_index
  end

  def test_find_by_contents
    contents_from_ferret = SpecialContent.find_by_contents('single table')
    assert_equal 1, contents_from_ferret.size
    assert_equal contents(:special), contents_from_ferret.first
    contents_from_ferret = SpecialContent.find_by_contents('title')
    assert contents_from_ferret.empty?
    
  end
end
