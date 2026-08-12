# EGOT Tracker — Design

**Date:** 2026-08-11
**Status:** Approved (design phase)

## Summary

Search a person and see how close they are to an EGOT — the four entertainment
awards: **E**mmy, **G**rammy, **O**scar, **T**ony. The result is a 2×2 grid of
big status tiles (green ✓ won / grey ✗ not), an EGOT verdict line, the specific
**wins** listed under each tile, and a best-effort **nominations** section.

Standalone personal project, sibling of `cast-ages`. Lives at `~/Code/egot-tracker`.

## Data source (proven)

- **Primary — Wikipedia MediaWiki API.** A person's category membership reliably
  encodes their award **wins**. One call per person
  (`action=query&prop=categories|pageprops|pageimages&titles=<Person>`) returns:
  - `categories` — matched against the four `"… Award winners"` families.
  - `pageprops.wikibase_item` — the person's Wikidata QID (for nominations).
  - `pageimages` — a thumbnail.
  - Name → page resolved via MediaWiki search (`list=search`).

  Verified in a proof-of-concept: Viola Davis (a real EGOT winner that Wikidata's
  structured `award received` data reports as **0/4**) is correctly detected as
  **4/4** from her Wikipedia categories.

- **Secondary (best-effort) — Wikidata `P1411` (nominated for).** Using the QID
  from `pageprops`, roll up nomination items to the four award roots over the
  multi-predicate path `(P31|P279|P361)*`. Inconsistent/incomplete by nature, so
  it is treated as enrichment only and degrades silently to empty.

- **Rejected:** IMDb (no free API, ToS), TMDb (no awards), OMDb (only a free-text
  awards blob, not per-award). Wikidata `award received` (`P166`) as a *primary*
  win source — proven incomplete (Viola Davis has zero P166 statements).

## Stack

Reuses the `cast-ages` stack:

- **Rails 8** (full stack, not API-only) with **Hotwire** (Turbo + Stimulus).
- **Tailwind CSS**.
- **Solid Cache** on SQLite wraps every outbound HTTP call. No other app database.
- **Deploy:** Kamal → ghcr → homelab box (`egot.kquizz.com`), Cloudflare tunnel.

## Core flow

1. User types a name → MediaWiki `list=search` returns candidate people (title +
   short description to disambiguate).
2. User picks a candidate → `PeopleController` fetches the profile (categories +
   QID + thumbnail), classifies wins, and best-effort-fetches nominations.
3. Result page renders the 2×2 grid, verdict, wins per award, and nominations.

## Backend components

Thin controllers delegate to services; results render as Turbo Frames.

- **`WikipediaClient`** — MediaWiki API wrapper.
  - `search(name)` → array of `Candidate(title:, description:)`.
  - `profile(title)` → `Profile(title:, thumbnail_url:, qid:, categories:)` from a
    single `prop=categories|pageprops|pageimages` call.
  - Sends a descriptive `User-Agent` (MediaWiki requires one). Cached.

- **`AwardClassifier`** — pure logic; no I/O. Given category titles, returns an
  `EgotStatus` with, per family (`emmy`, `grammy`, `oscar`, `tony`): `won?` and
  the list of specific win labels. A family is **won** iff any category contains
  that family's **award phrase** *and* a **win token** (`winn`, which matches
  winner / winners / winning):
  - Oscar → phrase `"Academy Award"`
  - Grammy → phrase `"Grammy Award"`
  - Emmy → phrase `"Emmy Award"` (matches Primetime and Daytime)
  - Tony → phrase `"Tony Award"`

  The award-phrase + win-token rule is required because Wikipedia does **not** use
  a single suffix. Wins appear as both `"… Award winners"` (e.g.
  `"Grammy Award winners"`) and `"… Award–winning …"` (e.g.
  `"Best Original Song Academy Award–winning songwriters"` — John Legend's Oscar,
  which a `"Academy Award winners"` suffix match would miss). The `winn` token
  also excludes `"… Award nominees"` categories.

  The phrases are safe against near-misses: BAFTA reads `"BAFTA Award"`,
  `"Academy of Country Music Award"` does not contain the contiguous phrase
  `"Academy Award"`, and `"Academy Honorary Award"` (honorary-only) is likewise
  excluded — acceptable for v1's competitive-leaning behavior.

  Win label = the category title with the `"Category:"` prefix stripped, shown
  as-is (e.g. `"Best Supporting Actress Academy Award winners"`). No fragile
  suffix surgery — the raw category is already human-readable.

- **`NominationsSource`** — best-effort Wikidata `P1411` rollup keyed by QID.
  Returns a per-family list of nomination labels, or `{}` on any error, empty
  result, or missing QID. Never raises to the caller.

- **Controllers:**
  - `SearchesController` — search-as-you-type; renders the candidate-list frame.
  - `PeopleController` — profile → classify → render the EGOT result page.

- **Caching:** `Rails.cache` (Solid Cache) wraps every MediaWiki and Wikidata
  call, keyed by endpoint + args, long TTL.

## Award logic & edge cases

- **Win detection:** a family is won iff any category title contains its marker.
- **EGOT score:** count of the four families won (0–4). EGOT iff all four.
- **Verdict copy:** `4/4` → "EGOT! 🏆"; otherwise "n/4 — missing: <families>".
- **Honorary vs competitive:** not distinguished by category name — accepted for
  v1. A small "Based on Wikipedia" footnote sets expectations.
- **No Wikipedia match:** friendly "no person found" state.
- **Ambiguous name:** the search step already shows candidates; the user picks.
- **Missing QID (no pageprops):** nominations skipped; wins unaffected.
- **Nominations source empty/errors:** the nominations section is omitted; the
  page otherwise renders normally.

## Frontend (Hotwire)

- Single page: search bar on top, Turbo-Frame results below.
- Search-as-you-type (Stimulus debounce, ~300ms) → candidate list (name +
  description).
- Pick a candidate → Turbo Frame loads the result:
  - 2×2 grid of tiles (award name, big ✓/✗), colour-coded.
  - Verdict line.
  - Per-tile win labels.
  - Best-effort nominations block (only if non-empty), labelled
    "nominations (best-effort — may be incomplete)".
  - "Based on Wikipedia" footnote.

## Testing

- **`AwardClassifier`** unit specs: a Viola Davis category fixture → 4/4 with
  correct win labels; the BAFTA and "Academy of Country Music" false-positive
  guards; a 0/4 case; the label-stripping.
- **`WikipediaClient`** specs with stubbed HTTP (WebMock): search parsing, profile
  parsing (categories + QID + thumbnail).
- **`NominationsSource`** specs: a populated rollup and the degrade-to-empty path
  (error, empty, missing QID).
- **Request specs** for the search flow and the person result flow.

## Deploy

- Kamal → ghcr → homelab box (`egot.kquizz.com`), mirroring `cast-ages`.

## Out of scope (v1)

- Distinguishing honorary from competitive awards.
- A reliable/complete nominations list (secondary source is best-effort only).
- Awards beyond the four EGOT families.
