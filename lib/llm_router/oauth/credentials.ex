defmodule LLMRouter.OAuth.Credentials do
  @moduledoc """
  Value object for an OAuth credential set.

  This module is intentionally pure data + small helpers. The library does
  not own any storage: callers persist credentials wherever they like
  (file, Vault, secrets manager, DB). JSON serialization via `to_map/1`
  and `from_map/1` is provided for convenience.

  The struct mirrors pi-ai's `OAuthCredentials` shape but uses Elixir
  conventions:

    * `:expires_at` is a `DateTime` (Pi uses milliseconds since epoch).
    * Provider-specific fields (e.g. OpenAI's `account_id`) go in `:extra`
      so the core struct stays stable across providers.
  """

  @type t :: %__MODULE__{
          provider: atom,
          access: String.t(),
          refresh: String.t(),
          expires_at: DateTime.t(),
          extra: map
        }

  @derive {Jason.Encoder, only: [:provider, :access, :refresh, :expires_at, :extra]}
  @enforce_keys [:provider, :access, :refresh, :expires_at]
  defstruct [:provider, :access, :refresh, :expires_at, extra: %{}]

  @doc """
  Returns `true` when the access token is at or past its expiration time.

  Callers typically refresh a bit before actual expiry; see `stale?/2`.
  """
  @spec expired?(t) :: boolean
  def expired?(%__MODULE__{expires_at: at}) do
    DateTime.compare(DateTime.utc_now(), at) != :lt
  end

  @doc """
  Returns `true` when the credentials will expire within `skew_seconds`.

  Useful for proactive refresh (recommended: 60-300 seconds).
  """
  @spec stale?(t, non_neg_integer) :: boolean
  def stale?(%__MODULE__{expires_at: at}, skew_seconds) when skew_seconds >= 0 do
    threshold = DateTime.add(DateTime.utc_now(), skew_seconds, :second)
    DateTime.compare(threshold, at) != :lt
  end

  @doc """
  Builds credentials from an `expires_in` duration (seconds from now), as
  returned by a token endpoint.
  """
  @spec build(atom, String.t(), String.t(), non_neg_integer, map) :: t
  def build(provider, access, refresh, expires_in_seconds, extra \\ %{})
      when is_atom(provider) and is_binary(access) and is_binary(refresh) and
             is_integer(expires_in_seconds) and is_map(extra) do
    %__MODULE__{
      provider: provider,
      access: access,
      refresh: refresh,
      expires_at: DateTime.add(DateTime.utc_now(), expires_in_seconds, :second),
      extra: extra
    }
  end

  @doc """
  Serializes to a JSON-compatible map. `:expires_at` becomes an ISO8601
  string; `:provider` becomes a string for cross-language portability.
  """
  @spec to_map(t) :: map
  def to_map(%__MODULE__{} = c) do
    %{
      "provider" => Atom.to_string(c.provider),
      "access" => c.access,
      "refresh" => c.refresh,
      "expires_at" => DateTime.to_iso8601(c.expires_at),
      "extra" => c.extra
    }
  end

  @doc """
  Parses a map (typically from `Jason.decode!/1`) into a `t/0`.

  Accepts either string or atom keys, and both ISO8601 strings and
  millisecond integers for `expires_at` (millisecond form matches Pi's
  on-disk format, which eases migration).
  """
  @spec from_map(map) :: {:ok, t} | {:error, term}
  def from_map(map) when is_map(map) do
    with {:ok, provider} <- fetch(map, :provider),
         {:ok, access} <- fetch(map, :access),
         {:ok, refresh} <- fetch(map, :refresh),
         {:ok, expires_raw} <- fetch(map, :expires_at),
         {:ok, expires_at} <- parse_expires(expires_raw) do
      extra =
        case fetch(map, :extra) do
          {:ok, m} when is_map(m) -> m
          _ -> %{}
        end

      {:ok,
       %__MODULE__{
         provider: to_atom(provider),
         access: access,
         refresh: refresh,
         expires_at: expires_at,
         extra: extra
       }}
    end
  end

  def from_map(_), do: {:error, :invalid_map}

  # --- private ---

  defp fetch(map, key) do
    case map do
      %{^key => v} when not is_nil(v) ->
        {:ok, v}

      _ ->
        sk = if is_atom(key), do: Atom.to_string(key), else: key

        case map do
          %{^sk => v} when not is_nil(v) -> {:ok, v}
          _ -> {:error, {:missing, key}}
        end
    end
  end

  defp parse_expires(%DateTime{} = dt), do: {:ok, dt}

  defp parse_expires(ms) when is_integer(ms) do
    DateTime.from_unix(ms, :millisecond)
  end

  defp parse_expires(str) when is_binary(str) do
    case DateTime.from_iso8601(str) do
      {:ok, dt, _} -> {:ok, dt}
      {:error, reason} -> {:error, {:invalid_expires_at, reason}}
    end
  end

  defp parse_expires(other), do: {:error, {:invalid_expires_at, other}}

  defp to_atom(a) when is_atom(a), do: a
  defp to_atom(s) when is_binary(s), do: String.to_atom(s)
end
