class SearchController < ApplicationController

  def show
    @search = Search.new params[:q], params[:page]
    @results = @search.run if @search.valid?
  end

end
