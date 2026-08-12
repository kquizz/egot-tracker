class PeopleController < ApplicationController
  # Renders the shell instantly (name + spinning skeleton tiles); the two lazy
  # Turbo Frames below fetch the real data and reveal it as it arrives.
  def show
    @title = params[:title]
  end

  def awards
    @title = params[:title]
    profile = WikipediaClient.new.profile(@title)
    @thumbnail_url = profile.thumbnail_url
    @status = AwardClassifier.call(profile.categories)
  end

  def nominations
    @title = params[:title]
    profile = WikipediaClient.new.profile(@title)
    @nominations = NominationsSource.new.for_qid(profile.qid)
  end
end
