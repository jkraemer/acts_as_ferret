require File.dirname(__FILE__) + '/../test_helper'

class RemoteIndexTest < Test::Unit::TestCase
  def setup
  end

  def test_raises_drb_errors
    @srv = ActsAsFerret::RemoteIndex.new :remote => 'druby://localhost:99999', :raise_drb_errors => true
    assert_raise DRb::DRbConnError do
      @srv.find_id_by_contents 'some query'
    end
  end

  def test_does_not_raise_drb_errors
    @srv = ActsAsFerret::RemoteIndex.new :remote => 'druby://localhost:99999', :raise_drb_errors => false
    total_hits, results = @srv.find_id_by_contents( 'some query' )
    assert_equal 0, total_hits
    assert results.empty?
  end
end
