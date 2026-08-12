class PeopleController < ApplicationController
  def show
    @profile = WikipediaClient.new.profile(params[:title])
    @status = AwardClassifier.call(@profile.categories)
    @nominations = NominationsSource.new.for_qid(@profile.qid)
  end
end
