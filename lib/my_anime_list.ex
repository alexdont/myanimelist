defmodule MyAnimeList do
  @moduledoc """
  A [MyAnimeList API v2](https://myanimelist.net/apiconfig/references/api/v2)
  client for Elixir, covering **both anime and manga**. The media type is
  the first argument on every call:

      MyAnimeList.search(:anime, "frieren", client_id)
      MyAnimeList.get(:manga, 2, client_id)
      MyAnimeList.list_statuses(:anime, access_token)

  Three levels of access map to three argument shapes:

    * **Public data** (search, details) needs only your app's `client_id`
      string — sent as the `X-MAL-CLIENT-ID` header, no user login.
    * **OAuth** (`authorize_url/3`, `exchange_code/3`, `refresh_token/3`)
      needs a `MyAnimeList.Client` with your `client_id`/`client_secret`/
      `redirect_uri`.
    * **List sync** (`list_statuses/3`, `update_list_status/5`, …) needs a
      user `access_token` string.

  Errors are values (`{:error, reason}`) — this module never raises.

  ## Testing

  Every request merges `req_options` (from the `Client`, a per-call
  `:req_options`, or `config :myanimelist, :req_options`), so you can point
  it at `Req.Test`:

      # config/test.exs
      config :myanimelist, req_options: [plug: {Req.Test, MyAnimeList}]
  """

  alias MyAnimeList.{Client, Token}

  @base_url "https://api.myanimelist.net/v2"
  @auth_url "https://myanimelist.net/v1/oauth2/authorize"
  @token_url "https://myanimelist.net/v1/oauth2/token"

  @search_fields "id,title,main_picture,mean,media_type,start_date"
  @common_detail "id,title,main_picture,alternative_titles,synopsis,mean,rank," <>
                   "popularity,num_list_users,genres,media_type,status,start_date,end_date"

  @media [:anime, :manga]

  @typedoc "Which MAL catalog to act on."
  @type media :: :anime | :manga

  # ── media-type dispatch ───────────────────────────────────────────

  defp path_seg(:anime), do: "anime"
  defp path_seg(:manga), do: "manga"

  defp list_seg(:anime), do: "animelist"
  defp list_seg(:manga), do: "mangalist"

  @doc """
  The `my_list_status` field that carries a user's progress for `media`
  (`"num_episodes_watched"` for anime, `"num_chapters_read"` for manga) —
  handy when building an `update_list_status/5` fields map.
  """
  @spec progress_key(media) :: String.t()
  def progress_key(:anime), do: "num_episodes_watched"
  def progress_key(:manga), do: "num_chapters_read"

  @doc "The valid list-status values MAL accepts for `media`."
  @spec statuses(media) :: [String.t()]
  def statuses(:anime), do: ~w(watching completed on_hold dropped plan_to_watch)
  def statuses(:manga), do: ~w(reading completed on_hold dropped plan_to_read)

  defp detail_fields(:manga),
    do: @common_detail <> ",num_volumes,num_chapters,authors{first_name,last_name}"

  defp detail_fields(:anime),
    do:
      @common_detail <>
        ",num_episodes,average_episode_duration,start_season,studios,source,rating"

  @doc "Public MAL page URL for a title."
  @spec page_url(media, term()) :: String.t()
  def page_url(media, id) when media in @media,
    do: "https://myanimelist.net/#{path_seg(media)}/#{id}"

  @doc "Whether a usable client id / access token was provided."
  @spec configured?(String.t() | nil) :: boolean()
  def configured?(v), do: is_binary(v) and v != ""

  # ── public data (client-id only) ──────────────────────────────────

  @doc """
  Search `media` by title. Returns
  `{:ok, [%{id, title, cover_url, score, media_type, year}]}`.

  Options: `:limit` (default 10), `:req_options`.
  """
  @spec search(media, String.t(), String.t(), keyword()) :: {:ok, [map()]} | {:error, term()}
  def search(media, query, client_id, opts \\ []) when media in @media do
    with true <- configured?(client_id) || {:error, :not_configured},
         params = [
           q: query,
           limit: Keyword.get(opts, :limit, 10),
           fields: @search_fields,
           nsfw: true
         ],
         {:ok, %{status: 200, body: %{"data" => data}}} <-
           http_get("/#{path_seg(media)}", client_id, params, opts) do
      {:ok, Enum.map(data, fn %{"node" => n} -> to_search_result(n) end)}
    else
      {:error, :not_configured} = err -> err
      other -> translate_error(other)
    end
  end

  @doc """
  Full metadata for a title id, normalized for enrichment. Common fields:
  `id, url, title, cover_url, synopsis, genres, score, rank, popularity,
  num_users, media_type, status, year, year_start, year_end`. Manga adds
  `num_chapters, num_volumes, authors`; anime adds `num_episodes, studios`
  (the other media's fields are present as `nil`/`[]`).

  Options: `:req_options`.
  """
  @spec get(media, term(), String.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def get(media, id, client_id, opts \\ []) when media in @media do
    with true <- configured?(client_id) || {:error, :not_configured},
         {:ok, %{status: 200, body: body}} <-
           http_get("/#{path_seg(media)}/#{id}", client_id, [fields: detail_fields(media)], opts) do
      {:ok, to_details(media, body)}
    else
      {:error, :not_configured} = err -> err
      other -> translate_error(other)
    end
  end

  # ── OAuth (per-user login) ────────────────────────────────────────
  # MAL uses authorization-code + PKCE, but ONLY supports the "plain"
  # challenge method — so code_challenge == code_verifier.

  @doc "True when the client has both an id and a secret configured."
  @spec oauth_ready?(Client.t()) :: boolean()
  def oauth_ready?(%Client{client_id: id, client_secret: secret}),
    do: configured?(id) and configured?(secret)

  @doc "A fresh PKCE code verifier (also used verbatim as the challenge)."
  @spec new_code_verifier() :: String.t()
  def new_code_verifier do
    # 64 random bytes → ~86 base64url chars, inside MAL's 43–128 range.
    :crypto.strong_rand_bytes(64) |> Base.url_encode64(padding: false)
  end

  @doc "MAL authorization URL to redirect the user to."
  @spec authorize_url(Client.t(), String.t(), String.t()) :: String.t()
  def authorize_url(%Client{} = c, state, code_verifier) do
    query =
      URI.encode_query(%{
        "response_type" => "code",
        "client_id" => c.client_id,
        "state" => state,
        "code_challenge" => code_verifier,
        "code_challenge_method" => "plain",
        "redirect_uri" => c.redirect_uri
      })

    @auth_url <> "?" <> query
  end

  @doc "Exchange an authorization code for a `MyAnimeList.Token`."
  @spec exchange_code(Client.t(), String.t(), String.t(), keyword()) ::
          {:ok, Token.t()} | {:error, term()}
  def exchange_code(%Client{} = c, code, code_verifier, opts \\ []) do
    token_request(
      c,
      %{
        "grant_type" => "authorization_code",
        "code" => code,
        "code_verifier" => code_verifier,
        "redirect_uri" => c.redirect_uri
      },
      opts
    )
  end

  @doc "Exchange a refresh token for a fresh `MyAnimeList.Token`."
  @spec refresh_token(Client.t(), String.t(), keyword()) :: {:ok, Token.t()} | {:error, term()}
  def refresh_token(%Client{} = c, refresh_token, opts \\ []) do
    token_request(c, %{"grant_type" => "refresh_token", "refresh_token" => refresh_token}, opts)
  end

  @doc """
  Return a non-expired token, refreshing via `refresh_token/3` if the
  current one is within a minute of expiry (or has no `expires_at`). The
  returned token may be the same struct — persist it if it changed.
  """
  @spec ensure_fresh(Client.t(), Token.t(), keyword()) :: {:ok, Token.t()} | {:error, term()}
  def ensure_fresh(%Client{} = c, %Token{} = token, opts \\ []) do
    if fresh?(token) do
      {:ok, token}
    else
      case token.refresh_token do
        rt when is_binary(rt) -> refresh_token(c, rt, opts)
        _ -> {:error, :no_refresh_token}
      end
    end
  end

  defp fresh?(%Token{expires_at: %DateTime{} = exp}),
    do: DateTime.compare(exp, DateTime.add(DateTime.utc_now(), 60, :second)) == :gt

  defp fresh?(_), do: false

  defp token_request(%Client{} = c, params, opts) do
    body = Map.merge(params, %{"client_id" => c.client_id, "client_secret" => c.client_secret})

    req =
      Req.new(url: @token_url, form: body, receive_timeout: 15_000, retry: false)
      |> Req.merge(req_options(c, opts))

    case Req.post(req) do
      {:ok, %{status: 200, body: %{"access_token" => _} = b}} -> {:ok, to_token(b)}
      other -> translate_error(other)
    end
  end

  defp to_token(b) do
    expires_at =
      case b["expires_in"] do
        n when is_integer(n) -> DateTime.add(DateTime.utc_now(), n, :second)
        _ -> nil
      end

    %Token{
      access_token: b["access_token"],
      refresh_token: b["refresh_token"],
      expires_at: expires_at
    }
  end

  # ── list sync (access-token) ──────────────────────────────────────

  @doc """
  The authenticated user's current progress for a title (episodes watched /
  chapters read), or `0` if it's not on their list. Useful to seed a push
  high-water mark so linking never regresses existing MAL progress.
  """
  @spec my_progress(media, String.t(), term(), keyword()) :: {:ok, integer()} | {:error, term()}
  def my_progress(media, access_token, id, opts \\ []) when media in @media do
    case authed_get("/#{path_seg(media)}/#{id}", access_token, [fields: "my_list_status"], opts) do
      {:ok, %{status: 200, body: body}} ->
        {:ok, get_in(body, ["my_list_status", progress_key(media)]) || 0}

      other ->
        translate_error(other)
    end
  end

  @doc """
  The authenticated user's whole list as `%{mal_id => list_status_map}`
  (the raw `list_status` object with `"status"`, `"score"`, the progress
  field, …). Paginates. Best-effort — returns `{:ok, map}` even on a
  partial/failed fetch.
  """
  @spec list_statuses(media, String.t(), keyword()) :: {:ok, %{optional(integer()) => map()}}
  def list_statuses(media, access_token, opts \\ []) when media in @media do
    url = "#{@base_url}/users/@me/#{list_seg(media)}?fields=list_status&limit=1000&nsfw=true"
    {:ok, paginate_list(access_token, url, %{}, 0, opts)}
  end

  defp paginate_list(_token, nil, acc, _page, _opts), do: acc
  defp paginate_list(_token, _url, acc, page, _opts) when page >= 20, do: acc

  defp paginate_list(access_token, url, acc, page, opts) do
    req =
      Req.new(
        url: url,
        headers: [{"authorization", "Bearer #{access_token}"}],
        receive_timeout: 15_000,
        retry: false
      )
      |> Req.merge(req_options(opts))

    case Req.get(req) do
      {:ok, %{status: 200, body: %{"data" => data} = body}} ->
        acc =
          Enum.reduce(data, acc, fn entry, m ->
            id = get_in(entry, ["node", "id"])
            ls = entry["list_status"] || %{}
            if is_integer(id), do: Map.put(m, id, ls), else: m
          end)

        paginate_list(access_token, get_in(body, ["paging", "next"]), acc, page + 1, opts)

      _ ->
        acc
    end
  end

  @doc """
  The authenticated user's list as `%{mal_id => score}` (score `0` = on the
  list but unrated; absent = not on the list).
  """
  @spec list_scores(media, String.t(), keyword()) :: {:ok, %{optional(integer()) => integer()}}
  def list_scores(media, access_token, opts \\ []) when media in @media do
    {:ok, m} = list_statuses(media, access_token, opts)
    {:ok, Map.new(m, fn {id, ls} -> {id, ls["score"] || 0} end)}
  end

  @doc "The authenticated user's MAL username, or `nil`."
  @spec username(String.t(), keyword()) :: String.t() | nil
  def username(access_token, opts \\ []) do
    case authed_get("/users/@me", access_token, [fields: "name"], opts) do
      {:ok, %{status: 200, body: %{"name" => name}}} -> name
      _ -> nil
    end
  end

  @doc """
  Update the authenticated user's list entry (`PATCH
  /{media}/{id}/my_list_status`). `fields` is a plain map, e.g.
  `%{num_episodes_watched: 12, status: "watching"}` for anime or
  `%{num_chapters_read: 12, status: "reading"}` for manga.
  """
  @spec update_list_status(media, String.t(), term(), map(), keyword()) ::
          {:ok, map()} | {:error, term()}
  def update_list_status(media, access_token, id, fields, opts \\ []) when media in @media do
    req =
      Req.new(
        method: :patch,
        url: "#{@base_url}/#{path_seg(media)}/#{id}/my_list_status",
        headers: [{"authorization", "Bearer #{access_token}"}],
        form: fields,
        receive_timeout: 15_000,
        retry: false
      )
      |> Req.merge(req_options(opts))

    case Req.request(req) do
      {:ok, %{status: 200, body: body}} -> {:ok, body}
      other -> translate_error(other)
    end
  end

  # ── display helpers ───────────────────────────────────────────────

  @doc "MAL publication/airing status → display label (anime + manga)."
  @spec status_label(String.t() | nil) :: String.t() | nil
  def status_label("currently_publishing"), do: "Ongoing"
  def status_label("currently_airing"), do: "Airing"
  def status_label("finished"), do: "Finished"
  def status_label("finished_airing"), do: "Finished"
  def status_label("not_yet_published"), do: "Not yet published"
  def status_label("not_yet_aired"), do: "Not yet aired"
  def status_label("on_hiatus"), do: "On Hiatus"
  def status_label("discontinued"), do: "Discontinued"
  def status_label(_), do: nil

  @doc ~S'Year range for display: "1997", "1997–2003", or "1997–" (ongoing).'
  @spec year_range(integer() | nil, integer() | nil) :: String.t() | nil
  def year_range(nil, _end_year), do: nil
  def year_range(y, y), do: Integer.to_string(y)
  def year_range(y, nil), do: "#{y}–"
  def year_range(from, to), do: "#{from}–#{to}"

  # ── HTTP ──────────────────────────────────────────────────────────

  defp http_get(path, client_id, params, opts) do
    req =
      Req.new(
        base_url: @base_url,
        headers: [{"x-mal-client-id", client_id}],
        receive_timeout: 15_000,
        retry: false
      )
      |> Req.merge(req_options(opts))

    Req.get(req, url: path, params: params)
  end

  defp authed_get(path, access_token, params, opts) do
    req =
      Req.new(
        base_url: @base_url,
        headers: [{"authorization", "Bearer #{access_token}"}],
        params: params,
        receive_timeout: 15_000,
        retry: false
      )
      |> Req.merge(req_options(opts))

    Req.get(req, url: path)
  end

  defp req_options(opts) when is_list(opts) do
    Keyword.get(opts, :req_options) || Application.get_env(:myanimelist, :req_options, [])
  end

  defp req_options(%Client{req_options: ro}, opts) do
    Keyword.get(opts, :req_options) || (ro != [] && ro) ||
      Application.get_env(:myanimelist, :req_options, [])
  end

  # ── normalization ─────────────────────────────────────────────────

  defp to_search_result(n) do
    %{
      id: n["id"],
      title: n["title"],
      cover_url: cover(n["main_picture"]),
      score: n["mean"],
      media_type: n["media_type"],
      year: year_of(n["start_date"])
    }
  end

  defp to_details(media, n) do
    base = %{
      id: n["id"],
      url: page_url(media, n["id"]),
      title: n["title"],
      cover_url: cover(n["main_picture"]),
      synopsis: n["synopsis"],
      genres: for(g <- n["genres"] || [], do: g["name"]),
      score: n["mean"],
      rank: n["rank"],
      popularity: n["popularity"],
      num_users: n["num_list_users"],
      media_type: n["media_type"],
      status: n["status"],
      year: year_of(n["start_date"]),
      start_date: n["start_date"],
      end_date: n["end_date"],
      year_start: year_of(n["start_date"]),
      year_end: year_of(n["end_date"])
    }

    Map.merge(base, media_details(media, n))
  end

  defp media_details(:manga, n) do
    %{
      num_chapters: n["num_chapters"],
      num_volumes: n["num_volumes"],
      authors: people(n["authors"]),
      num_episodes: nil,
      studios: []
    }
  end

  defp media_details(:anime, n) do
    %{
      num_episodes: n["num_episodes"],
      studios: names(n["studios"]),
      num_chapters: nil,
      num_volumes: nil,
      authors: []
    }
  end

  defp cover(%{"large" => l}) when is_binary(l) and l != "", do: l
  defp cover(%{"medium" => m}) when is_binary(m) and m != "", do: m
  defp cover(_), do: nil

  defp year_of(<<y::binary-size(4), _::binary>>) do
    case Integer.parse(y) do
      {n, _} -> n
      _ -> nil
    end
  end

  defp year_of(_), do: nil

  defp people(list) when is_list(list) do
    list
    |> Enum.map(fn a ->
      node = a["node"] || %{}
      [node["first_name"], node["last_name"]] |> Enum.reject(&(&1 in [nil, ""])) |> Enum.join(" ")
    end)
    |> Enum.reject(&(&1 == ""))
  end

  defp people(_), do: []

  defp names(list) when is_list(list),
    do: list |> Enum.map(& &1["name"]) |> Enum.reject(&(&1 in [nil, ""]))

  defp names(_), do: []

  defp translate_error({:ok, %{status: 404}}), do: {:error, :not_found}
  defp translate_error({:ok, %{status: 401}}), do: {:error, :unauthorized}
  defp translate_error({:ok, %{status: status}}), do: {:error, {:http, status}}
  defp translate_error({:error, reason}), do: {:error, {:transport, reason}}
  defp translate_error(_), do: {:error, :unknown}
end
