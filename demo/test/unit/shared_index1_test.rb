require File.dirname(__FILE__) + '/../test_helper'

class SharedIndex1Test < Test::Unit::TestCase
  fixtures :shared_index1s, :shared_index2s

  def setup
    SharedIndex1.rebuild_index(SharedIndex2)
  end

  def test_find
    assert_equal shared_index1s(:first), SharedIndex1.find(1)
    assert_equal shared_index2s(:first), SharedIndex2.find(1)
  end

  def test_find_id_by_contents
    result = SharedIndex1.find_id_by_contents("first")
    assert_equal 2, result.size
  end

  def test_find_by_contents_one_class
    result = SharedIndex1.find_by_contents("first")
    assert_equal 1, result.size
    assert_equal shared_index1s(:first), result.first

    result = SharedIndex1.find_by_contents("name:first", :models => [SharedIndex1])
    assert_equal 1, result.size
    assert_equal shared_index1s(:first), result.first
  end

  def custom_query
    result = SharedIndex1.find_by_contents("name:first class_name:SharedIndex1")
    assert_equal 1, result.size
    assert_equal shared_index1s(:first), result.first
  end

  def test_find_by_contents_all_classes
    result = SharedIndex1.find_by_contents("first", :models => :all)
    assert_equal 2, result.size
    assert result.include?(shared_index1s(:first))
    assert result.include?(shared_index2s(:first))

    result = SharedIndex1.find_by_contents("name:first", :models => [SharedIndex2])
    assert_equal 2, result.size
    assert result.include?(shared_index1s(:first))
    assert result.include?(shared_index2s(:first))

  end

  def test_destroy
    result = SharedIndex1.find_by_contents("first OR another", :models => :all)
    assert_equal 4, result.size
    shared_index1s(:first).destroy
    result = SharedIndex1.find_by_contents("first OR another", :models => :all)
    assert_equal 3, result.size
  end

  def test_update
    assert SharedIndex1.find_by_contents("new").empty?
    shared_index1s(:first).name = "new name"
    shared_index1s(:first).save
    assert_equal 1, SharedIndex1.find_by_contents("new").size
    assert_equal 1, SharedIndex1.find_by_contents("new").size
    assert_equal 1, SharedIndex1.find_by_contents("new", :models => [SharedIndex2]).size
    assert_equal 0, SharedIndex2.find_by_contents("new").size
  end
end
