# EGOT Tracker

Search a person and see how close they are to an EGOT — Emmy, Grammy, Oscar, Tony.

## How it works
- **Wins** come from Wikipedia category membership (reliable). Detection matches an
  award phrase (e.g. `Academy Award`) plus a win token (`winn`), which catches both
  the `… Award winners` and `… Award–winning …` category forms and skips nominees.
- **Nominations** are a best-effort Wikidata `P1411` rollup (may be incomplete);
  they degrade silently to empty and never block the wins.
- No API keys required — Wikipedia and Wikidata are unauthenticated.

## Setup
1. `bundle install`
2. `bin/dev`
3. Open http://localhost:3000

## Stack
Rails 8, Hotwire, Tailwind, MediaWiki + Wikidata APIs, Solid Cache. Deployed with Kamal.

## Tests
`bundle exec rspec`
