require "rails_helper"

RSpec.describe "People", type: :request do
  let(:wikipedia) { instance_double(WikipediaClient) }
  let(:nominations) { instance_double(NominationsSource) }

  before do
    allow(WikipediaClient).to receive(:new).and_return(wikipedia)
    allow(NominationsSource).to receive(:new).and_return(nominations)
  end

  describe "GET /people/:title (shell)" do
    it "renders the name and a spinning skeleton without hitting the data sources" do
      get person_path(title: "Viola Davis")

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Viola Davis")
      expect(response.body).to include("animate-spin")
      # all four labels are known instantly, before any network call
      expect(response.body).to include("Emmy", "Grammy", "Oscar", "Tony")
      # the awards + nominations frames lazy-load their own endpoints
      expect(response.body).to include(person_awards_path(title: "Viola Davis"))
      expect(response.body).to include(person_nominations_path(title: "Viola Davis"))
    end
  end

  describe "GET /people/awards (wins frame)" do
    it "renders the grid, verdict, and wins with a staggered reveal" do
      allow(wikipedia).to receive(:profile).with("John Legend").and_return(
        WikipediaClient::Profile.new(title: "John Legend", qid: "Q44857",
          thumbnail_url: nil, categories: [
            "Category:Grammy Award winners",
            "Category:Primetime Emmy Award winners",
            "Category:Tony Award winners",
            "Category:Best Original Song Academy Award–winning songwriters"
          ])
      )

      get person_awards_path(title: "John Legend")

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("EGOT")
      expect(response.body).to include("Grammy Award winners")
      expect(response.body).to include("egot-reveal")
    end

    it "shows a partial verdict and the missing award for a non-EGOT" do
      allow(wikipedia).to receive(:profile).with("Beyoncé").and_return(
        WikipediaClient::Profile.new(title: "Beyoncé", qid: "Q36153",
          thumbnail_url: nil, categories: ["Category:Grammy Award winners"])
      )

      get person_awards_path(title: "Beyoncé")

      expect(response.body).to include("1/4")
      expect(response.body).to include("Oscar")
    end
  end

  describe "GET /people/nominations (best-effort frame)" do
    it "renders nominations when present" do
      allow(wikipedia).to receive(:profile).with("Someone").and_return(
        WikipediaClient::Profile.new(title: "Someone", qid: "Q1",
          thumbnail_url: nil, categories: [])
      )
      allow(nominations).to receive(:for_qid).with("Q1")
        .and_return(oscar: ["Academy Award for Best Actor"])

      get person_nominations_path(title: "Someone")

      expect(response.body).to include("Academy Award for Best Actor")
      expect(response.body).to include("best-effort")
    end

    it "renders an empty frame when there are no nominations" do
      allow(wikipedia).to receive(:profile).with("Nobody").and_return(
        WikipediaClient::Profile.new(title: "Nobody", qid: nil,
          thumbnail_url: nil, categories: [])
      )
      allow(nominations).to receive(:for_qid).with(nil).and_return({})

      get person_nominations_path(title: "Nobody")

      expect(response).to have_http_status(:ok)
      expect(response.body).not_to include("best-effort")
    end
  end
end
