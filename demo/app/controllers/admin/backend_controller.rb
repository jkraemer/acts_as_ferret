class Admin::BackendController < AdminAreaController

  def search
    @query = params[:query] || ''
    unless @query.blank?
      @results = Content.find_by_contents @query
    end
  end
end
