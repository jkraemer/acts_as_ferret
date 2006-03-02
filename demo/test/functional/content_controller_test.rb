require File.dirname(__FILE__) + '/../test_helper'
require 'content_controller'

# Re-raise errors caught by the controller.
class ContentController; def rescue_action(e) raise e end; end

class ContentControllerTest < Test::Unit::TestCase
  fixtures :contents

  def setup
    index = Ferret::Index::Index.new( :path => Content.class_index_dir, :create => true	)
    index.flush
    index.close
    @controller = ContentController.new
    @request    = ActionController::TestRequest.new
    @response   = ActionController::TestResponse.new
  end

  def test_index
    get :index
    assert_response :success
    assert_template 'list'
  end

  def test_list
    get :list

    assert_response :success
    assert_template 'list'

    assert_not_nil assigns(:contents)
  end

  def test_show
    get :show, :id => 1

    assert_response :success
    assert_template 'show'

    assert_not_nil assigns(:content)
    assert assigns(:content).valid?
  end

  def test_new
    get :new

    assert_response :success
    assert_template 'new'

    assert_not_nil assigns(:content)
  end

  def test_create
    num_contents = Content.count

    post :create, :content => {}

    assert_response :redirect
    assert_redirected_to :action => 'list'

    assert_equal num_contents + 1, Content.count
  end

  def test_edit
    get :edit, :id => 1

    assert_response :success
    assert_template 'edit'

    assert_not_nil assigns(:content)
    assert assigns(:content).valid?
  end

  def test_update
    post :update, :id => 1
    assert_response :redirect
    assert_redirected_to :action => 'show', :id => 1
  end

  def test_destroy
    assert_not_nil Content.find(1)

    post :destroy, :id => 1
    assert_response :redirect
    assert_redirected_to :action => 'list'

    assert_raise(ActiveRecord::RecordNotFound) {
      Content.find(1)
    }
  end

  def test_search
    post :create, :content => { :title => 'my title', :description => 'a little bit of content' }
    get :search
    assert_template 'search'
    assert_nil assigns(:results)

    post :search, :query => 'title'
    assert_template 'search'
    assert_equal 1, assigns(:results).size
    
    post :search, :query => 'monkey'
    assert_template 'search'
    assert assigns(:results).empty?
    
    # check that model changes are picked up by the searcher (searchers have to
    # be reopened to reflect changes done to the index)
    # wait for the searcher to age a bit (it seems fs timestamp resolution is
    # only 1 sec)
    sleep 1
    post :create, :content => { :title => 'another content object', :description => 'description goes hers' }
    post :search, :query => 'another'
    assert_template 'search'
    assert_equal 1, assigns(:results).size
    
  end
end
