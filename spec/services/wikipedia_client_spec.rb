require "rails_helper"

RSpec.describe WikipediaClient do
  subject(:client) { described_class.new }

  describe "#search" do
    it "returns candidate people with title and description" do
      body = {
        pages: [
          { title: "John Legend", description: "American singer and songwriter",
            thumbnail: { url: "//img/jl.jpg" } },
          { title: "Legend (John Legend album)", description: "2022 studio album",
            thumbnail: nil }
        ]
      }.to_json

      stub_request(:get, "https://en.wikipedia.org/w/rest.php/v1/search/page")
        .with(query: hash_including("q" => "john legend"))
        .to_return(status: 200, body: body, headers: { "Content-Type" => "application/json" })

      results = client.search("john legend")

      expect(results.map(&:title)).to eq(["John Legend", "Legend (John Legend album)"])
      expect(results.first.description).to eq("American singer and songwriter")
    end

    it "returns [] for a blank query without calling the API" do
      expect(client.search("  ")).to eq([])
      expect(a_request(:get, /wikipedia/)).not_to have_been_made
    end
  end
end
