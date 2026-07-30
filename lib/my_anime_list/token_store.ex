defmodule MyAnimeList.TokenStore do
  @moduledoc """
  Behaviour for persisting per-owner MAL tokens.

  MyAnimeList ships no schema or database dependency — you supply storage
  against your own app (Ecto table, ETS, a GenServer, anything). Implement
  these three callbacks and MyAnimeList stays out of your persistence
  layer entirely. `owner` is whatever key identifies a user in your app
  (a user id, a struct, …).

      defmodule MyApp.MALTokens do
        @behaviour MyAnimeList.TokenStore

        @impl true
        def get_token(user_id), do: # → %MyAnimeList.Token{} | nil

        @impl true
        def put_token(user_id, token), do: # persist, → :ok

        @impl true
        def delete_token(user_id), do: # → :ok
      end
  """

  @callback get_token(owner :: term()) :: MyAnimeList.Token.t() | nil
  @callback put_token(owner :: term(), MyAnimeList.Token.t()) :: :ok | {:error, term()}
  @callback delete_token(owner :: term()) :: :ok | {:error, term()}
end
