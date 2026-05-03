defmodule Pado.LLMRouter.Credential.OAuth.Credentials do
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

  def expired?(%__MODULE__{expires_at: at}) do
    DateTime.compare(DateTime.utc_now(), at) != :lt
  end

  def stale?(%__MODULE__{expires_at: at}, skew_seconds) when skew_seconds >= 0 do
    threshold = DateTime.add(DateTime.utc_now(), skew_seconds, :second)
    DateTime.compare(threshold, at) != :lt
  end

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

  def to_map(%__MODULE__{} = c) do
    %{
      "provider" => Atom.to_string(c.provider),
      "access" => c.access,
      "refresh" => c.refresh,
      "expires_at" => DateTime.to_iso8601(c.expires_at),
      "extra" => c.extra
    }
  end

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
