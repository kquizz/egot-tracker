require "rails_helper"

RSpec.describe "Searches", type: :request do
  it "renders the search page" do
    get root_path
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("EGOT")
  end

  it "renders candidates for a query" do
    candidates = [
      WikipediaClient::Candidate.new(title: "John Legend",
        description: "American singer and songwriter", thumbnail_url: nil)
    ]
    allow_any_instance_of(WikipediaClient).to receive(:search)
      .with("john legend").and_return(candidates)

    get search_path, params: { q: "john legend" }
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("John Legend")
    expect(response.body).to include("American singer and songwriter")
  end
end
