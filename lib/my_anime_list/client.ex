defmodule MyAnimeList.Client do
  @moduledoc """
  OAuth app credentials for MyAnimeList.

  Public-data calls (`MyAnimeList.search/4`, `MyAnimeList.get/4`) only need
  a bare `client_id` string, but the OAuth flow needs the full app
  registration:

      client = %MyAnimeList.Client{
        client_id: System.fetch_env!("MAL_CLIENT_ID"),
        client_secret: System.fetch_env!("MAL_CLIENT_SECRET"),
        redirect_uri: "https://example.com/auth/mal/callback"
      }

  `req_options` is merged into every request this client makes — the seam
  for `Req.Test` in your tests, or for custom retry/timeout behaviour.
  """

  @enforce_keys [:client_id]
  defstruct [:client_id, :client_secret, :redirect_uri, req_options: []]

  @type t :: %__MODULE__{
          client_id: String.t(),
          client_secret: String.t() | nil,
          redirect_uri: String.t() | nil,
          req_options: keyword()
        }
end
