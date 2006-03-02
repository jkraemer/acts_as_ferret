class ContentController < ApplicationController
  def index
    list
    render :action => 'list'
  end

  def list
    @content_pages, @contents = paginate :contents, :per_page => 10
  end

  def show
    @content = Content.find(params[:id])
  end

  def new
    @content = Content.new
  end

  def create
    @content = Content.new(params[:content])
    if @content.save
      flash[:notice] = 'Content was successfully created.'
      redirect_to :action => 'list'
    else
      render :action => 'new'
    end
  end

  def edit
    @content = Content.find(params[:id])
  end

  def update
    @content = Content.find(params[:id])
    if @content.update_attributes(params[:content])
      flash[:notice] = 'Content was successfully updated.'
      redirect_to :action => 'show', :id => @content
    else
      render :action => 'edit'
    end
  end

  def destroy
    Content.find(params[:id]).destroy
    redirect_to :action => 'list'
  end

  def search
    @query = params[:query] || ''
    unless @query.blank?
      @results = Content.find_by_contents @query
    end
  end
end
