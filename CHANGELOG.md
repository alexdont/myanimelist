# Changelog

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
