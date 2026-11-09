# MyAnimeList

A [MyAnimeList API v2](https://myanimelist.net/apiconfig/references/api/v2)
client for Elixir, covering **both anime and manga**. The media type is the
first argument on every call.

```elixir
def deps do
  [{:myanimelist, "~> 0.2"}]
end
```

## Public data — just a client id

Search and metadata authenticate with only your app's `client_id` (the
`X-MAL-CLIENT-ID` header), no user login:

```elixir
MyAnimeList.search(:anime, "frieren", client_id)
#=> {:ok, [%{id: 52991, title: "Sousou no Frieren", cover_url: "…", score: 8.9, media_type: "tv", year: 2023}, …]}

{:ok, manga} = MyAnimeList.get(:manga, 2, client_id)
manga.num_chapters   #=> 162   (anime results carry num_episodes/studios instead)
```

Details come back normalized with a stable shape across both media — the
other media's fields are present as `nil`/`[]`.

## OAuth login

MAL uses authorization-code + PKCE (plain challenge). Wrap your app
registration in a `MyAnimeList.Client`:

```elixir
client = %MyAnimeList.Client{
  client_id: System.fetch_env!("MAL_CLIENT_ID"),
  client_secret: System.fetch_env!("MAL_CLIENT_SECRET"),
  redirect_uri: "https://example.com/auth/mal/callback"
}

verifier = MyAnimeList.new_code_verifier()      # stash in the session
url = MyAnimeList.authorize_url(client, state, verifier)   # redirect the user here

# in your callback:
{:ok, token} = MyAnimeList.exchange_code(client, code, verifier)
#=> %MyAnimeList.Token{access_token: "…", refresh_token: "…", expires_at: ~U[…]}
```

Keep it fresh before an authenticated call:

```elixir
{:ok, token} = MyAnimeList.ensure_fresh(client, token)   # refreshes if near expiry
```

## List sync — an access token

```elixir
{:ok, statuses} = MyAnimeList.list_statuses(:anime, token.access_token)
#=> %{52991 => %{"status" => "watching", "score" => 9, "num_episodes_watched" => 12}, …}

MyAnimeList.update_list_status(:manga, token.access_token, 2,
  %{status: "reading", num_chapters_read: 100})

MyAnimeList.my_progress(:anime, token.access_token, 52991)   #=> {:ok, 12}
```

`progress_key/1` and `statuses/1` give you the media-correct field name and
the valid status vocabulary when building an update:

```elixir
MyAnimeList.progress_key(:anime)  #=> "num_episodes_watched"
MyAnimeList.statuses(:manga)      #=> ["reading", "completed", "on_hold", "dropped", "plan_to_read"]
```

## Anime extras

```elixir
{:ok, a} = MyAnimeList.get(:anime, 52991, client_id, include: [:related, :themes])
a.season            #=> %{year: 2023, season: "fall"}
a.episode_duration  #=> 1475   (seconds)
a.openings          #=> [%{n: nil, song: "Yuusha", artist: "YOASOBI", eps: "eps 1-16"}]
a.related           #=> [%{id: 59978, title: "…", relation: "sequel", cover_url: "…"}, …]

# MAL keeps each season as its own entry; walk them into one series:
{:ok, seasons} = MyAnimeList.seasons(40028, client_id)
Enum.map(seasons, & &1.title)
#=> ["Shingeki no Kyojin", "… Season 2", "… Season 3", "… Season 3 Part 2", "… The Final Season", …]

{year, season} = MyAnimeList.season_of(Date.utc_today())   #=> {2026, "fall"}
{:ok, airing} = MyAnimeList.seasonal(year, season, client_id, limit: 50)
{:ok, top} = MyAnimeList.ranking(:anime, "airing", client_id, limit: 10)
```

Updating progress: MAL's update form wants `num_watched_episodes` for anime
(its responses say `num_episodes_watched`, and sending that back is a 400).
`progress_fields/4` gets it right and completes the entry at a known total:

```elixir
fields = MyAnimeList.progress_fields(:anime, 12, 12)
#=> %{num_watched_episodes: 12, status: "completed", finish_date: "2026-11-09"}
MyAnimeList.update_list_status(:anime, token.access_token, 52991, fields)
```

## Persisting tokens

MyAnimeList ships **no schema and no database dependency**. Implement the
`MyAnimeList.TokenStore` behaviour against your own storage:

```elixir
defmodule MyApp.MALTokens do
  @behaviour MyAnimeList.TokenStore

  @impl true
  def get_token(user_id), do: # → %MyAnimeList.Token{} | nil
  @impl true
  def put_token(user_id, token), do: # persist, → :ok
  @impl true
  def delete_token(user_id), do: :ok
end
```

## Errors & testing

Every function returns values and never raises. Failures come back as an
`{:error, reason}` tuple, where `reason` is one of `:not_found`,
`:unauthorized`, `:not_configured`, a `:http`/status pair, or a
`:transport`/exception pair. Every request merges `req_options`, so point
it at `Req.Test`:

```elixir
# config/test.exs
config :myanimelist, req_options: [plug: {Req.Test, MyAnimeList}]
```

## License

MIT © Alexander Don
