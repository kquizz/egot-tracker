# EGOT Tracker Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A Rails app where you search a person and see how close they are to an EGOT — a 2×2 grid of Emmy/Grammy/Oscar/Tony checks, the specific wins listed underneath, and a best-effort nominations section.

**Architecture:** Full-stack Rails 8 with Hotwire (Turbo Frames drive search-as-you-type and the result swap). Wins come from Wikipedia MediaWiki category membership (reliable); nominations are a best-effort Wikidata `P1411` rollup that degrades silently to empty. Three services: `WikipediaClient` (HTTP, cached), `AwardClassifier` (pure win-detection logic), `NominationsSource` (best-effort Wikidata, never raises). No app database beyond the cache SQLite.

**Tech Stack:** Ruby 3.3.2, Rails 8.1.3, Hotwire (Turbo + Stimulus), Tailwind CSS, Solid Cache (SQLite), Faraday for HTTP, RSpec + WebMock.

---

## File Structure

```
app/
  services/
    wikipedia_client.rb     # MediaWiki: search(name), profile(title). Cached.
    award_classifier.rb     # category titles -> EgotStatus (per-family won? + wins)
    nominations_source.rb   # Wikidata P1411 rollup by QID, best-effort, never raises
  controllers/
    searches_controller.rb  # GET / and /search?q= -> candidate list frame
    people_controller.rb    # GET /people/:title -> EGOT result page
  models/
    egot_status.rb          # value object: per-family won? + win labels + score
  views/
    searches/               # search page + candidate list partial
    people/                 # result page: 2x2 grid, verdict, wins, nominations
  javascript/controllers/
    search_controller.js    # Stimulus: debounce the search input
config/
  deploy.yml                # Kamal -> ghcr -> homelab
spec/
  services/award_classifier_spec.rb
  services/wikipedia_client_spec.rb
  services/nominations_source_spec.rb
  requests/searches_spec.rb
  requests/people_spec.rb
```

**The four EGOT families** are referenced everywhere as a single ordered list of
`[key, label, phrase]`. Defined once in `AwardClassifier::FAMILIES` (Task 3) and
reused by views. Order for the 2×2 grid: Emmy, Grammy, Oscar, Tony.

---

## Task 1: Scaffold the Rails app

**Files:**
- Create: the app skeleton under `~/Code/egot-tracker`
- Modify: `Gemfile`

- [ ] **Step 1: Generate the app** (Tailwind + SQLite; Rails 8 gives Hotwire, Propshaft, Solid Cache, Kamal)

The repo already exists at `~/Code/egot-tracker` with a `docs/` dir and git
history. Generate into it:

```bash
cd ~/Code/egot-tracker
rails new . --css=tailwind --skip-test --force
```

`--skip-test` skips Minitest (we use RSpec). `--force` only overwrites
Rails-generated files; `docs/` is untouched.

- [ ] **Step 2: Add gems**

Add to `Gemfile`:

```ruby
gem "faraday"

group :development, :test do
  gem "rspec-rails"
end

group :test do
  gem "webmock"
end
```

- [ ] **Step 3: Install and init RSpec**

```bash
cd ~/Code/egot-tracker
bundle install
bin/rails generate rspec:install
```

Expected: creates `.rspec`, `spec/spec_helper.rb`, `spec/rails_helper.rb`.

- [ ] **Step 4: Enable WebMock in specs**

Add to `spec/rails_helper.rb`, right after the `require 'rspec/rails'` line:

```ruby
require 'webmock/rspec'
WebMock.disable_net_connect!(allow_localhost: true)
```

- [ ] **Step 5: Verify the app boots**

```bash
cd ~/Code/egot-tracker
bin/rails runner 'puts "boots ok"'
```

Expected: prints `boots ok`.

- [ ] **Step 6: Commit**

```bash
cd ~/Code/egot-tracker
git add -A
git commit -m "chore: scaffold Rails 8 app with Tailwind and RSpec"
```

---

## Task 2: EgotStatus value object (pure, full TDD)

**Files:**
- Create: `app/models/egot_status.rb`
- Test: `spec/models/egot_status_spec.rb`

`EgotStatus` holds the per-family result and answers the "how close" questions.
A family entry is `{ won: bool, wins: [String] }` keyed by family key symbol.

- [ ] **Step 1: Write the failing test**

```ruby
# spec/models/egot_status_spec.rb
require "rails_helper"

RSpec.describe EgotStatus do
  def status(overrides = {})
    base = { emmy: { won: false, wins: [] }, grammy: { won: false, wins: [] },
             oscar: { won: false, wins: [] }, tony: { won: false, wins: [] } }
    described_class.new(base.merge(overrides))
  end

  it "counts the number of award families won" do
    s = status(emmy: { won: true, wins: ["a"] }, oscar: { won: true, wins: ["b"] })
    expect(s.score).to eq(2)
  end

  it "is an EGOT only when all four are won" do
    all = { emmy: { won: true, wins: [] }, grammy: { won: true, wins: [] },
            oscar: { won: true, wins: [] }, tony: { won: true, wins: [] } }
    expect(described_class.new(all).egot?).to be(true)
    expect(status(emmy: { won: true, wins: [] }).egot?).to be(false)
  end

  it "lists the labels of the missing families" do
    s = status(emmy: { won: true, wins: [] }, grammy: { won: true, wins: [] },
               oscar: { won: true, wins: [] })
    expect(s.missing_labels).to eq(["Tony"])
  end

  it "exposes won? and wins per family" do
    s = status(grammy: { won: true, wins: ["Best New Artist"] })
    expect(s.won?(:grammy)).to be(true)
    expect(s.wins(:grammy)).to eq(["Best New Artist"])
    expect(s.won?(:tony)).to be(false)
  end
end
```

- [ ] **Step 2: Run it to verify it fails**

```bash
cd ~/Code/egot-tracker
bundle exec rspec spec/models/egot_status_spec.rb
```

Expected: FAIL with `uninitialized constant EgotStatus`.

- [ ] **Step 3: Implement**

```ruby
# app/models/egot_status.rb
class EgotStatus
  LABELS = { emmy: "Emmy", grammy: "Grammy", oscar: "Oscar", tony: "Tony" }.freeze

  def initialize(families)
    @families = families
  end

  def won?(key) = @families.fetch(key)[:won]
  def wins(key) = @families.fetch(key)[:wins]
  def score = LABELS.keys.count { |k| won?(k) }
  def egot? = score == 4
  def missing_labels = LABELS.select { |k, _| !won?(k) }.values
end
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
cd ~/Code/egot-tracker
bundle exec rspec spec/models/egot_status_spec.rb
```

Expected: PASS (4 examples).

- [ ] **Step 5: Commit**

```bash
cd ~/Code/egot-tracker
git add app/models/egot_status.rb spec/models/egot_status_spec.rb
git commit -m "feat: EgotStatus value object (score, egot?, missing)"
```

---

## Task 3: AwardClassifier (pure logic, full TDD)

**Files:**
- Create: `app/services/award_classifier.rb`
- Test: `spec/services/award_classifier_spec.rb`

Detection rule (verified against live Wikipedia data): a family is **won** iff any
category title contains the family's **award phrase** AND a **win token** (`winn`,
matching winner/winners/winning). This catches both `"… Award winners"` and
`"… Award–winning …"` forms and excludes `"… Award nominees"`.

- [ ] **Step 1: Write the failing test**

```ruby
# spec/services/award_classifier_spec.rb
require "rails_helper"

RSpec.describe AwardClassifier do
  def classify(cats) = described_class.call(cats)

  it "detects all four families for a real EGOT winner (Viola Davis categories)" do
    cats = [
      "Category:Best Supporting Actress Academy Award winners",
      "Category:Grammy Award winners",
      "Category:Primetime Emmy Award winners",
      "Category:Tony Award winners",
      "Category:Best Supporting Actress BAFTA Award winners",
      "Category:Drama Desk Award winners"
    ]
    status = classify(cats)
    expect(status.egot?).to be(true)
    expect(status.score).to eq(4)
  end

  it "detects an Oscar from the '…Award–winning' songwriter form (John Legend)" do
    status = classify(["Category:Best Original Song Academy Award–winning songwriters"])
    expect(status.won?(:oscar)).to be(true)
    expect(status.won?(:grammy)).to be(false)
  end

  it "does not treat BAFTA as an Oscar" do
    status = classify(["Category:Best Actress BAFTA Award winners"])
    expect(status.won?(:oscar)).to be(false)
  end

  it "does not treat an Academy of Country Music award as an Oscar" do
    status = classify(["Category:Academy of Country Music Award winners"])
    expect(status.won?(:oscar)).to be(false)
  end

  it "ignores nominee categories" do
    status = classify(["Category:Grammy Award nominees"])
    expect(status.won?(:grammy)).to be(false)
  end

  it "collects the specific win labels with the Category: prefix stripped" do
    status = classify([
      "Category:Grammy Award winners",
      "Category:Best New Artist Grammy Award winners"
    ])
    expect(status.wins(:grammy)).to contain_exactly(
      "Grammy Award winners", "Best New Artist Grammy Award winners"
    )
  end

  it "returns all-false for a person with no EGOT categories" do
    status = classify(["Category:American film actors", "Category:Living people"])
    expect(status.score).to eq(0)
  end
end
```

- [ ] **Step 2: Run it to verify it fails**

```bash
cd ~/Code/egot-tracker
bundle exec rspec spec/services/award_classifier_spec.rb
```

Expected: FAIL with `uninitialized constant AwardClassifier`.

- [ ] **Step 3: Implement**

```ruby
# app/services/award_classifier.rb
class AwardClassifier
  # [key, label, award phrase] — order defines the 2x2 grid (Emmy, Grammy, Oscar, Tony)
  FAMILIES = [
    [:emmy,   "Emmy",   "Emmy Award"],
    [:grammy, "Grammy", "Grammy Award"],
    [:oscar,  "Oscar",  "Academy Award"],
    [:tony,   "Tony",   "Tony Award"]
  ].freeze

  WIN_TOKEN = /winn/i

  def self.call(category_titles)
    names = Array(category_titles).map { |c| c.to_s.delete_prefix("Category:") }
    families = FAMILIES.to_h do |key, _label, phrase|
      wins = names.select { |name| name.include?(phrase) && name.match?(WIN_TOKEN) }
      [key, { won: wins.any?, wins: wins }]
    end
    EgotStatus.new(families)
  end
end
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
cd ~/Code/egot-tracker
bundle exec rspec spec/services/award_classifier_spec.rb
```

Expected: PASS (7 examples). Note the John Legend category uses an en-dash
(`–`) in `Award–winning`; the phrase `"Academy Award"` still matches because the
dash follows `Award`.

- [ ] **Step 5: Commit**

```bash
cd ~/Code/egot-tracker
git add app/services/award_classifier.rb spec/services/award_classifier_spec.rb
git commit -m "feat: AwardClassifier detects EGOT wins from categories"
```

---

## Task 4: WikipediaClient#search (TDD with WebMock)

**Files:**
- Create: `app/services/wikipedia_client.rb`
- Test: `spec/services/wikipedia_client_spec.rb`

Uses the MediaWiki REST search endpoint, which returns title + description +
thumbnail (verified live). MediaWiki requires a descriptive `User-Agent`.

- [ ] **Step 1: Write the failing test**

```ruby
# spec/services/wikipedia_client_spec.rb
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
```

- [ ] **Step 2: Run it to verify it fails**

```bash
cd ~/Code/egot-tracker
bundle exec rspec spec/services/wikipedia_client_spec.rb
```

Expected: FAIL with `uninitialized constant WikipediaClient`.

- [ ] **Step 3: Implement search + the client shell**

```ruby
# app/services/wikipedia_client.rb
require "faraday"

class WikipediaClient
  API = "https://en.wikipedia.org/w/api.php".freeze
  REST_SEARCH = "https://en.wikipedia.org/w/rest.php/v1/search/page".freeze
  USER_AGENT = "egot-tracker/0.1 (https://egot.kquizz.com)".freeze

  Candidate = Struct.new(:title, :description, :thumbnail_url, keyword_init: true)

  def initialize(cache: Rails.cache)
    @cache = cache
  end

  def search(query)
    query = query.to_s.strip
    return [] if query.empty?

    payload = get_json(REST_SEARCH, q: query, limit: 8)
    Array(payload["pages"]).map do |page|
      Candidate.new(
        title: page["title"],
        description: page["description"],
        thumbnail_url: page.dig("thumbnail", "url")
      )
    end
  end

  private

  def get_json(url, params)
    @cache.fetch("wp:#{url}:#{params.sort.to_h}", expires_in: 7.days) do
      response = connection.get(url, params)
      raise "MediaWiki #{response.status}" unless response.success?

      JSON.parse(response.body)
    end
  end

  def connection
    @connection ||= Faraday.new do |f|
      f.headers["User-Agent"] = USER_AGENT
      f.headers["Accept"] = "application/json"
    end
  end
end
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
cd ~/Code/egot-tracker
bundle exec rspec spec/services/wikipedia_client_spec.rb
```

Expected: PASS (2 examples).

- [ ] **Step 5: Commit**

```bash
cd ~/Code/egot-tracker
git add app/services/wikipedia_client.rb spec/services/wikipedia_client_spec.rb
git commit -m "feat: WikipediaClient#search over the REST search endpoint"
```

---

## Task 5: WikipediaClient#profile (TDD with WebMock)

**Files:**
- Modify: `app/services/wikipedia_client.rb`
- Test: `spec/services/wikipedia_client_spec.rb` (add a context)

One `action=query` call returns categories + the Wikidata QID (pageprops) + a
thumbnail (verified live). The `query.pages` object is keyed by page id, so read
the first value.

- [ ] **Step 1: Write the failing test**

```ruby
  describe "#profile" do
    it "returns categories, the Wikidata QID, and a thumbnail" do
      body = {
        query: {
          pages: {
            "12345" => {
              title: "John Legend",
              pageprops: { wikibase_item: "Q44857" },
              thumbnail: { source: "https://img/jl.jpg" },
              categories: [
                { title: "Category:Grammy Award winners" },
                { title: "Category:Tony Award winners" }
              ]
            }
          }
        }
      }.to_json

      stub_request(:get, "https://en.wikipedia.org/w/api.php")
        .with(query: hash_including("titles" => "John Legend", "action" => "query"))
        .to_return(status: 200, body: body, headers: { "Content-Type" => "application/json" })

      profile = client.profile("John Legend")

      expect(profile.title).to eq("John Legend")
      expect(profile.qid).to eq("Q44857")
      expect(profile.thumbnail_url).to eq("https://img/jl.jpg")
      expect(profile.categories).to include("Category:Grammy Award winners")
    end

    it "handles a page with no pageprops or thumbnail" do
      body = { query: { pages: { "1" => { title: "Nobody", categories: [] } } } }.to_json
      stub_request(:get, "https://en.wikipedia.org/w/api.php")
        .to_return(status: 200, body: body, headers: { "Content-Type" => "application/json" })

      profile = client.profile("Nobody")
      expect(profile.qid).to be_nil
      expect(profile.thumbnail_url).to be_nil
      expect(profile.categories).to eq([])
    end
  end
```

- [ ] **Step 2: Run it to verify it fails**

```bash
cd ~/Code/egot-tracker
bundle exec rspec spec/services/wikipedia_client_spec.rb -e profile
```

Expected: FAIL with `undefined method 'profile'`.

- [ ] **Step 3: Implement profile**

Add the `Profile` struct below `Candidate`:

```ruby
  Profile = Struct.new(:title, :qid, :thumbnail_url, :categories, keyword_init: true)
```

Add the public method (after `#search`):

```ruby
  def profile(title)
    payload = get_json(API,
      action: "query", format: "json",
      prop: "categories|pageprops|pageimages",
      ppprop: "wikibase_item", piprop: "thumbnail", pithumbsize: 200,
      cllimit: 500, clshow: "!hidden", titles: title)

    page = payload.dig("query", "pages")&.values&.first || {}
    Profile.new(
      title: page["title"] || title,
      qid: page.dig("pageprops", "wikibase_item"),
      thumbnail_url: page.dig("thumbnail", "source"),
      categories: Array(page["categories"]).map { |c| c["title"] }
    )
  end
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
cd ~/Code/egot-tracker
bundle exec rspec spec/services/wikipedia_client_spec.rb
```

Expected: PASS (4 examples).

- [ ] **Step 5: Commit**

```bash
cd ~/Code/egot-tracker
git add app/services/wikipedia_client.rb spec/services/wikipedia_client_spec.rb
git commit -m "feat: WikipediaClient#profile (categories, QID, thumbnail)"
```

---

## Task 6: NominationsSource (best-effort Wikidata, TDD)

**Files:**
- Create: `app/services/nominations_source.rb`
- Test: `spec/services/nominations_source_spec.rb`

Best-effort: given a QID, query Wikidata SPARQL for `P1411` (nominated for) items,
roll each up to the four award roots over `(P31|P279|P361)*`, and return a
per-family list of nomination labels. **Never raises** — returns `{}` on nil QID,
HTTP error, or empty result. The four roots per family are taken from the POC.

- [ ] **Step 1: Write the failing test**

```ruby
# spec/services/nominations_source_spec.rb
require "rails_helper"

RSpec.describe NominationsSource do
  subject(:source) { described_class.new }

  def sparql_stub(bindings)
    body = { results: { bindings: bindings } }.to_json
    stub_request(:get, "https://query.wikidata.org/sparql")
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
    stub_request(:get, "https://query.wikidata.org/sparql").to_return(status: 500)
    expect(source.for_qid("Q123")).to eq({})
  end

  it "returns {} on a timeout rather than raising" do
    stub_request(:get, "https://query.wikidata.org/sparql").to_timeout
    expect(source.for_qid("Q123")).to eq({})
  end
end
```

- [ ] **Step 2: Run it to verify it fails**

```bash
cd ~/Code/egot-tracker
bundle exec rspec spec/services/nominations_source_spec.rb
```

Expected: FAIL with `uninitialized constant NominationsSource`.

- [ ] **Step 3: Implement**

```ruby
# app/services/nominations_source.rb
require "faraday"

class NominationsSource
  ENDPOINT = "https://query.wikidata.org/sparql".freeze
  USER_AGENT = "egot-tracker/0.1 (https://egot.kquizz.com)".freeze

  # family => array of Wikidata root QIDs (from the proven POC rollup)
  ROOTS = {
    emmy:   %w[Q1044427 Q123737 Q1364556],
    grammy: %w[Q41254],
    oscar:  %w[Q19020],
    tony:   %w[Q191874]
  }.freeze

  def initialize(cache: Rails.cache)
    @cache = cache
  end

  def for_qid(qid)
    return {} if qid.blank?

    rows = @cache.fetch("noms:#{qid}", expires_in: 7.days) { query(qid) }
    group(rows)
  rescue StandardError
    {}
  end

  private

  def query(qid)
    response = connection.get(ENDPOINT, query: sparql(qid), format: "json")
    raise "Wikidata #{response.status}" unless response.success?

    JSON.parse(response.body).dig("results", "bindings") || []
  end

  def group(rows)
    rows.each_with_object({}) do |row, acc|
      family = row.dig("family", "value")&.to_sym
      label = row.dig("nomLabel", "value")
      next unless family && label

      (acc[family] ||= []) << label
    end
  end

  def sparql(qid)
    values = ROOTS.flat_map { |fam, qids| qids.map { |q| "(wd:#{q} \"#{fam}\")" } }.join(" ")
    <<~SPARQL
      SELECT DISTINCT ?family ?nomLabel WHERE {
        wd:#{qid} wdt:P1411 ?nom .
        ?nom (wdt:P31|wdt:P279|wdt:P361)* ?root .
        VALUES (?root ?family) { #{values} }
        SERVICE wikibase:label { bd:serviceParam wikibase:language "en". }
      }
    SPARQL
  end

  def connection
    @connection ||= Faraday.new do |f|
      f.headers["User-Agent"] = USER_AGENT
      f.headers["Accept"] = "application/sparql-results+json"
    end
  end
end
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
cd ~/Code/egot-tracker
bundle exec rspec spec/services/nominations_source_spec.rb
```

Expected: PASS (4 examples). The timeout case is caught by the `rescue` in
`for_qid` (Faraday raises, block returns nothing cached, rescue returns `{}`).

- [ ] **Step 5: Commit**

```bash
cd ~/Code/egot-tracker
git add app/services/nominations_source.rb spec/services/nominations_source_spec.rb
git commit -m "feat: NominationsSource best-effort Wikidata P1411 rollup"
```

---

## Task 7: Search page + candidate list (controller, Turbo Frame, request spec)

**Files:**
- Create: `app/controllers/searches_controller.rb`
- Create: `app/views/searches/show.html.erb`
- Create: `app/views/searches/_candidate.html.erb`
- Modify: `config/routes.rb`
- Test: `spec/requests/searches_spec.rb`

- [ ] **Step 1: Add routes**

```ruby
# config/routes.rb  (inside Rails.application.routes.draw)
root "searches#show"
get "search", to: "searches#show", as: :search
```

- [ ] **Step 2: Write the failing request spec**

```ruby
# spec/requests/searches_spec.rb
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
```

- [ ] **Step 3: Run it to verify it fails**

```bash
cd ~/Code/egot-tracker
bundle exec rspec spec/requests/searches_spec.rb
```

Expected: FAIL — `uninitialized constant SearchesController` or missing route.

- [ ] **Step 4: Implement controller**

```ruby
# app/controllers/searches_controller.rb
class SearchesController < ApplicationController
  def show
    @query = params[:q].to_s
    @candidates = @query.present? ? WikipediaClient.new.search(@query) : []
  end
end
```

- [ ] **Step 5: Implement views**

```erb
<%# app/views/searches/show.html.erb %>
<div class="max-w-2xl mx-auto p-6">
  <h1 class="text-3xl font-bold mb-1">EGOT Tracker</h1>
  <p class="text-gray-500 mb-6">How close is anyone to an Emmy, Grammy, Oscar & Tony?</p>

  <%= form_with url: search_path, method: :get,
        data: { controller: "search", turbo_frame: "candidates" } do |f| %>
    <%= f.search_field :q, value: @query, autofocus: true,
          placeholder: "Search a person…",
          data: { action: "input->search#submit" },
          class: "w-full border rounded-lg px-4 py-3 text-lg" %>
  <% end %>

  <%= turbo_frame_tag "candidates", class: "mt-4 flex flex-col gap-1" do %>
    <% @candidates.each do |candidate| %>
      <%= render "candidate", candidate: candidate %>
    <% end %>
  <% end %>
</div>
```

```erb
<%# app/views/searches/_candidate.html.erb %>
<%= link_to person_path(title: candidate.title), data: { turbo_frame: "_top" },
      class: "flex items-center gap-3 p-2 rounded-lg hover:bg-gray-100" do %>
  <% if candidate.thumbnail_url %>
    <%= image_tag candidate.thumbnail_url.start_with?("//") ? "https:#{candidate.thumbnail_url}" : candidate.thumbnail_url,
          class: "w-10 h-10 rounded-full object-cover", loading: "lazy" %>
  <% else %>
    <div class="w-10 h-10 rounded-full bg-gray-200"></div>
  <% end %>
  <div>
    <div class="font-medium"><%= candidate.title %></div>
    <div class="text-gray-500 text-sm"><%= candidate.description %></div>
  </div>
<% end %>
```

Note: `person_path` is defined in Task 8. Between tasks the candidate links 404;
that's acceptable. Re-run this spec after Task 8 to confirm green.

- [ ] **Step 6: Run tests to verify they pass**

```bash
cd ~/Code/egot-tracker
bundle exec rspec spec/requests/searches_spec.rb
```

Expected: the first example passes. The second raises on `person_path` until Task
8 — implement Task 8's route, then re-run. (If working strictly, add the Task 8
route block first.)

- [ ] **Step 7: Commit**

```bash
cd ~/Code/egot-tracker
git add app/controllers/searches_controller.rb app/views/searches config/routes.rb spec/requests/searches_spec.rb
git commit -m "feat: search page with Turbo Frame candidate list"
```

---

## Task 8: Person result page — 2×2 grid, verdict, wins, nominations

**Files:**
- Create: `app/controllers/people_controller.rb`
- Create: `app/views/people/show.html.erb`
- Create: `app/views/people/_award_tile.html.erb`
- Modify: `config/routes.rb`
- Test: `spec/requests/people_spec.rb`

- [ ] **Step 1: Add route**

Title can contain spaces and slashes; capture the rest of the path.

```ruby
# config/routes.rb
get "people/:title", to: "people#show", as: :person, constraints: { title: /.+/ }
```

- [ ] **Step 2: Write the failing request spec**

```ruby
# spec/requests/people_spec.rb
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
```

- [ ] **Step 3: Run it to verify it fails**

```bash
cd ~/Code/egot-tracker
bundle exec rspec spec/requests/people_spec.rb
```

Expected: FAIL — `uninitialized constant PeopleController`.

- [ ] **Step 4: Implement controller**

```ruby
# app/controllers/people_controller.rb
class PeopleController < ApplicationController
  def show
    @profile = WikipediaClient.new.profile(params[:title])
    @status = AwardClassifier.call(@profile.categories)
    @nominations = NominationsSource.new.for_qid(@profile.qid)
  end
end
```

- [ ] **Step 5: Implement views**

```erb
<%# app/views/people/show.html.erb %>
<div class="max-w-2xl mx-auto p-6">
  <%= link_to "← New search", root_path, class: "text-blue-600" %>

  <div class="flex items-center gap-4 mt-2 mb-6">
    <% if @profile.thumbnail_url %>
      <%= image_tag @profile.thumbnail_url, class: "w-16 h-16 rounded-full object-cover" %>
    <% end %>
    <div>
      <h1 class="text-3xl font-bold"><%= @profile.title %></h1>
      <p class="text-lg font-medium">
        <% if @status.egot? %>
          🏆 EGOT!
        <% else %>
          <%= @status.score %>/4 — missing: <%= @status.missing_labels.to_sentence %>
        <% end %>
      </p>
    </div>
  </div>

  <div class="grid grid-cols-2 gap-4">
    <% AwardClassifier::FAMILIES.each do |key, label, _phrase| %>
      <%= render "award_tile", key: key, label: label, status: @status %>
    <% end %>
  </div>

  <% if @nominations.present? %>
    <div class="mt-8">
      <h2 class="font-semibold">Nominations
        <span class="text-gray-400 text-sm font-normal">(best-effort — may be incomplete)</span>
      </h2>
      <% @nominations.each do |family, labels| %>
        <div class="mt-2">
          <div class="text-sm text-gray-500"><%= EgotStatus::LABELS[family] %></div>
          <ul class="list-disc list-inside">
            <% labels.each do |label| %><li><%= label %></li><% end %>
          </ul>
        </div>
      <% end %>
    </div>
  <% end %>

  <p class="mt-8 text-xs text-gray-400">Based on Wikipedia.</p>
</div>
```

```erb
<%# app/views/people/_award_tile.html.erb %>
<div class="border rounded-xl p-4 text-center <%= status.won?(key) ? 'bg-green-50 border-green-300' : 'bg-gray-50' %>">
  <div class="text-4xl"><%= status.won?(key) ? "✅" : "❌" %></div>
  <div class="font-bold mt-1"><%= label %></div>
  <ul class="mt-2 text-xs text-gray-600 space-y-0.5">
    <% status.wins(key).each do |win| %>
      <li><%= win %></li>
    <% end %>
  </ul>
</div>
```

- [ ] **Step 6: Run tests to verify they pass**

```bash
cd ~/Code/egot-tracker
bundle exec rspec spec/requests/people_spec.rb spec/requests/searches_spec.rb
```

Expected: PASS. `person_path` now exists, so the Task 7 search spec goes green too.

- [ ] **Step 7: Commit**

```bash
cd ~/Code/egot-tracker
git add app/controllers/people_controller.rb app/views/people config/routes.rb spec/requests/people_spec.rb
git commit -m "feat: person result page with EGOT grid, verdict, wins, nominations"
```

---

## Task 9: Stimulus debounce for search-as-you-type

**Files:**
- Create: `app/javascript/controllers/search_controller.js`

- [ ] **Step 1: Implement the Stimulus controller**

```javascript
// app/javascript/controllers/search_controller.js
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  submit() {
    clearTimeout(this.timeout)
    this.timeout = setTimeout(() => {
      this.element.requestSubmit()
    }, 300)
  }
}
```

- [ ] **Step 2: Verify registration**

Rails 8 importmap auto-registers Stimulus controllers via
`eagerLoadControllersFrom("controllers", application)` in
`app/javascript/controllers/index.js`. If that file uses an explicit list instead,
add:

```javascript
import SearchController from "./search_controller"
application.register("search", SearchController)
```

- [ ] **Step 3: Manual smoke test**

```bash
cd ~/Code/egot-tracker
bin/dev
```

Open http://localhost:3000, type "Viola Davis", confirm candidates appear ~300ms
after you stop typing, click her, and confirm 4/4 with an EGOT verdict. (This is
the first end-to-end hit against live Wikipedia — no API key needed.)

- [ ] **Step 4: Commit**

```bash
cd ~/Code/egot-tracker
git add app/javascript/controllers/search_controller.js
git commit -m "feat: debounce search input with Stimulus"
```

---

## Task 10: Deploy config (Kamal → ghcr → homelab)

**Files:**
- Modify: `config/deploy.yml`
- Modify: `.kamal/secrets`
- Reference: homelab web-app deploy pattern (kamal-proxy on `192.168.50.220`, ghcr
  registry PAT in `~/.zshrc`, Cloudflare tunnel route added in the CF dashboard).

- [ ] **Step 1: Configure `config/deploy.yml`**

```yaml
service: egot-tracker
image: kquizz/egot-tracker

servers:
  web:
    - 192.168.50.220

proxy:
  host: egot.kquizz.com   # add this route in the Cloudflare tunnel dashboard
  app_port: 3000

registry:
  server: ghcr.io
  username: kquizz
  password:
    - KAMAL_REGISTRY_PASSWORD

env:
  secret:
    - RAILS_MASTER_KEY
  clear:
    SOLID_QUEUE_IN_PUMA: true

volumes:
  - "egot_tracker_storage:/rails/storage"   # SQLite (cache) persistence

builder:
  arch: arm64
```

No third-party API keys are needed — Wikipedia and Wikidata are unauthenticated.

- [ ] **Step 2: Set Kamal secrets**

```bash
# .kamal/secrets  (references, not literal values)
KAMAL_REGISTRY_PASSWORD=$KAMAL_REGISTRY_PASSWORD
RAILS_MASTER_KEY=$(cat config/master.key)
```

`$KAMAL_REGISTRY_PASSWORD` comes from the login shell env (`~/.zshrc`), matching
the homelab web-app deploy pattern.

- [ ] **Step 3: First deploy**

```bash
cd ~/Code/egot-tracker
kamal setup
```

Expected: image builds, pushes to ghcr, boots on `192.168.50.220`. Then add the
`egot.kquizz.com` route in the Cloudflare tunnel dashboard and load it.

- [ ] **Step 4: Commit**

```bash
cd ~/Code/egot-tracker
git add config/deploy.yml .kamal/secrets
git commit -m "chore: Kamal deploy to homelab via ghcr and Cloudflare tunnel"
```

---

## Task 11: Full suite + README

**Files:**
- Create: `README.md`

- [ ] **Step 1: Run the full suite**

```bash
cd ~/Code/egot-tracker
bundle exec rspec
```

Expected: all green.

- [ ] **Step 2: Write the README**

```markdown
# EGOT Tracker

Search a person and see how close they are to an EGOT — Emmy, Grammy, Oscar, Tony.

## How it works
- **Wins** come from Wikipedia category membership (reliable).
- **Nominations** are a best-effort Wikidata `P1411` rollup (may be incomplete).
- No API keys required — Wikipedia and Wikidata are unauthenticated.

## Setup
1. `bundle install`
2. `bin/dev`
3. Open http://localhost:3000

## Stack
Rails 8, Hotwire, Tailwind, MediaWiki + Wikidata APIs, Solid Cache. Deployed with Kamal.

## Tests
`bundle exec rspec`
```

- [ ] **Step 3: Commit**

```bash
cd ~/Code/egot-tracker
git add README.md
git commit -m "docs: README"
```

---

## Self-Review Notes

- **Spec coverage:** search + candidates (Task 4, 7, 9); wins via categories
  (Task 3, 5, 8); the songwriter-Oscar `Award–winning` case and false-positive
  guards (Task 3); 2×2 grid + verdict + missing award (Task 2, 8); best-effort
  nominations with silent degradation (Task 6, 8); caching (every client wraps
  `Rails.cache`); "Based on Wikipedia" footnote (Task 8); deploy (Task 10). All
  spec sections map to tasks.
- **Placeholder scan:** none — every code step shows complete code.
- **Type consistency:** `EgotStatus` API (`score`, `egot?`, `missing_labels`,
  `won?`, `wins`, `LABELS`) is defined in Task 2 and used identically in Task 3
  (`AwardClassifier.call` returns it), Task 8 views, and the nominations partial.
  `AwardClassifier::FAMILIES` (`[key, label, phrase]`) defined in Task 3, iterated
  in the Task 8 grid. `WikipediaClient::Candidate` (`title`, `description`,
  `thumbnail_url`) and `Profile` (`title`, `qid`, `thumbnail_url`, `categories`)
  are defined in Tasks 4–5 and referenced with matching fields in Tasks 7–8 specs
  and views. `NominationsSource#for_qid` returns a `family => [labels]` hash used
  in Task 8.
- **Known cross-task dependency:** Task 7's `_candidate` partial references
  `person_path`, defined in Task 8 (flagged in Task 7 Step 5/6).
- **Nominations root QIDs** (`NominationsSource::ROOTS`) are the ones proven in the
  POC; if a family later shows gaps, add roots there — isolated to one constant.
