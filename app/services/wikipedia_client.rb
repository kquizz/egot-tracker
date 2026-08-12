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
