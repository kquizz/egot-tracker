require "rails_helper"

RSpec.describe NominationsSource do
  subject(:source) { described_class.new }

  SPARQL_URL = %r{\Ahttps://query\.wikidata\.org/sparql}

  def sparql_stub(bindings)
    body = { results: { bindings: bindings } }.to_json
    stub_request(:get, SPARQL_URL)
      .to_return(status: 200, body: body, headers: { "Content-Type" => "application/json" })
  end

  it "returns per-family nomination labels for a QID" do
    sparql_stub([
      { "family" => { "value" => "oscar" },
        "nomLabel" => { "value" => "Academy Award for Best Actor" } },
      { "family" => { "value" => "tony" },
        "nomLabel" => { "value" => "Tony Award for Best Actor in a Play" } }
    ])

    result = source.for_qid("Q123")
    expect(result[:oscar]).to eq(["Academy Award for Best Actor"])
    expect(result[:tony]).to eq(["Tony Award for Best Actor in a Play"])
    expect(result[:emmy]).to be_nil
  end

  it "returns {} when the QID is nil, without calling the API" do
    expect(source.for_qid(nil)).to eq({})
    expect(a_request(:get, /wikidata/)).not_to have_been_made
  end

  it "returns {} on an HTTP error rather than raising" do
    stub_request(:get, SPARQL_URL).to_return(status: 500)
    expect(source.for_qid("Q123")).to eq({})
  end

  it "returns {} on a timeout rather than raising" do
    stub_request(:get, SPARQL_URL).to_timeout
    expect(source.for_qid("Q123")).to eq({})
  end
end
