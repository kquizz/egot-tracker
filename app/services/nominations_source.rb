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
