defmodule Pado.Agent.Session do
  alias Pado.Agent.Session.Entry

  @type t :: %__MODULE__{
          id: String.t(),
          version: pos_integer(),
          entries: [Entry.t()],
          created_at: DateTime.t(),
          updated_at: DateTime.t()
        }

  @enforce_keys [:id, :created_at, :updated_at]
  defstruct [
    :id,
    :created_at,
    :updated_at,
    version: 1,
    entries: []
  ]

  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{} = session) do
    %{
      "type" => "session",
      "version" => session.version,
      "id" => session.id,
      "created_at" => encode_datetime(session.created_at),
      "updated_at" => encode_datetime(session.updated_at),
      "entries" => Enum.map(session.entries, &Entry.to_map/1)
    }
  end

  @spec from_map(map()) :: {:ok, t()} | {:error, term()}
  def from_map(%{"type" => "session"} = map) do
    with {:ok, created_at} <- decode_datetime(map["created_at"]),
         {:ok, updated_at} <- decode_datetime(map["updated_at"]),
         {:ok, entries} <- decode_entries(Map.get(map, "entries", [])) do
      {:ok,
       %__MODULE__{
         id: map["id"],
         version: map["version"] || 1,
         entries: entries,
         created_at: created_at,
         updated_at: updated_at
       }}
    end
  end

  def from_map(map), do: {:error, {:invalid_session_map, map}}

  defp decode_entries(entries) when is_list(entries) do
    entries
    |> Enum.reduce_while({:ok, []}, fn map, {:ok, acc} ->
      case Entry.from_map(map) do
        {:ok, entry} -> {:cont, {:ok, [entry | acc]}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, entries} -> {:ok, Enum.reverse(entries)}
      error -> error
    end
  end

  defp decode_entries(entries), do: {:error, {:invalid_entries, entries}}

  defp encode_datetime(nil), do: nil
  defp encode_datetime(%DateTime{} = datetime), do: DateTime.to_iso8601(datetime)

  defp decode_datetime(nil), do: {:ok, nil}

  defp decode_datetime(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, datetime, _offset} -> {:ok, datetime}
      {:error, reason} -> {:error, {:invalid_datetime, value, reason}}
    end
  end

  defp decode_datetime(value), do: {:error, {:invalid_datetime, value}}
end
