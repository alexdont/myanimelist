defmodule MyAnimeList.Token do
  @moduledoc """
  An OAuth token set. `expires_at` is computed from the `expires_in` MAL
  returns, so `MyAnimeList.ensure_fresh/3` can refresh before it lapses.
  Persist all three fields in your own store (see `MyAnimeList.TokenStore`).
  """

  @enforce_keys [:access_token]
  defstruct [:access_token, :refresh_token, :expires_at]

  @type t :: %__MODULE__{
          access_token: String.t(),
          refresh_token: String.t() | nil,
          expires_at: DateTime.t() | nil
        }
end
