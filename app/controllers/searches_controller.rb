class SearchesController < ApplicationController
  def show
    @query = params[:q].to_s
    @candidates = @query.present? ? WikipediaClient.new.search(@query) : []
  end
end
