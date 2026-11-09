# Changelog

## 0.2.0

Anime gets its own parts.

- `get/4` now returns the anime fields it already asked MAL for and used to
  drop: `episode_duration` (seconds), `season` (`%{year, season}`),
  `broadcast`, `source`, `rating`; and, for both media, the other names
  (`title_en`, `title_ja`, `synonyms`).
- `get/4` takes `include: [:related, :themes, :recommendations]` to fetch
  related entries (with MAL's relation type), opening/ending songs and
  recommendations in the same request.
- `seasons/3` — every season of a series in order, walking MAL's
  prequel/sequel links from any one entry (films and specials in between
  skipped).
- `themes/3` and `parse_theme/1` — opening/ending songs as
  `%{n, song, artist, eps}`.
- `seasonal/4`, `season_of/1`, `ranking/4` — the broadcast season's anime
  and MAL's rankings (anime and manga).
- `progress_fields/4` — the update form for "now at N": the field name MAL's
  form actually accepts (`num_watched_episodes` for anime, not the response's
  `num_episodes_watched`, which MAL rejects with a 400), completed with a
  `finish_date` at a known total.
- `rate/5`, `delete_list_status/4`, `list_entries/3` (the list with each
  title's name, cover, totals and episode length).
- Docs: `update_list_status/5`'s anime example used the response spelling,
  which MAL refuses; fixed.

## 0.1.0

Initial release.

- MyAnimeList API v2 client for **both anime and manga** — media type is
  the first argument on every call.
- Public data (client-id only): `search/4`, `get/4`, normalized to a stable
  shape across media.
- OAuth (PKCE plain) via a `MyAnimeList.Client`: `new_code_verifier/0`,
  `authorize_url/3`, `exchange_code/4`, `refresh_token/3`, `ensure_fresh/3`;
  tokens as a `MyAnimeList.Token` struct with a computed `expires_at`.
- List sync (access token): `list_statuses/3`, `list_scores/3`,
  `my_progress/4`, `update_list_status/5`, `username/2`.
- Helpers: `progress_key/1`, `statuses/1`, `page_url/2`, `status_label/1`,
  `year_range/2`.
- `MyAnimeList.TokenStore` behaviour for persistence — no Ecto dependency.
- Errors as values; a `req_options` seam for `Req.Test`.
