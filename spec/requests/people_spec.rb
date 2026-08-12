require "rails_helper"

RSpec.describe "People", type: :request do
  let(:wikipedia) { instance_double(WikipediaClient) }
  let(:nominations) { instance_double(NominationsSource) }

  before do
    allow(WikipediaClient).to receive(:new).and_return(wikipedia)
    allow(NominationsSource).to receive(:new).and_return(nominations)
  end

  it "shows the EGOT grid, verdict, and wins for a person" do
    allow(wikipedia).to receive(:profile).with("John Legend").and_return(
      WikipediaClient::Profile.new(title: "John Legend", qid: "Q44857",
        thumbnail_url: nil, categories: [
          "Category:Grammy Award winners",
          "Category:Primetime Emmy Award winners",
          "Category:Tony Award winners",
          "Category:Best Original Song Academy Award–winning songwriters"
        ])
    )
    allow(nominations).to receive(:for_qid).with("Q44857").and_return({})

    get person_path(title: "John Legend")
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("John Legend")
    expect(response.body).to include("EGOT")
    expect(response.body).to include("Grammy Award winners")
  end

  it "shows a partial verdict and the missing award for a non-EGOT" do
    allow(wikipedia).to receive(:profile).with("Beyoncé").and_return(
      WikipediaClient::Profile.new(title: "Beyoncé", qid: "Q36153",
        thumbnail_url: nil, categories: ["Category:Grammy Award winners"])
    )
    allow(nominations).to receive(:for_qid).with("Q36153").and_return({})

    get person_path(title: "Beyoncé")
    expect(response.body).to include("1/4")
    expect(response.body).to include("Emmy")
  end

  it "renders best-effort nominations when present" do
    allow(wikipedia).to receive(:profile).with("Someone").and_return(
      WikipediaClient::Profile.new(title: "Someone", qid: "Q1",
        thumbnail_url: nil, categories: [])
    )
    allow(nominations).to receive(:for_qid).with("Q1")
      .and_return(oscar: ["Academy Award for Best Actor"])

    get person_path(title: "Someone")
    expect(response.body).to include("Academy Award for Best Actor")
    expect(response.body).to include("best-effort")
  end
end
