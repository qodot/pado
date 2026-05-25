defmodule Pado.Agent.Session do
  alias Pado.Agent.Session.Entry
  alias Pado.LLM.Message
  alias Pado.LLM.Message.{Assistant, ToolResult, User}

  @type t :: %__MODULE__{
          id: String.t(),
          version: pos_integer(),
          provider: atom() | nil,
          model: String.t() | nil,
          reasoning_effort: atom() | nil,
          entries: [Entry.t()],
          created_at: DateTime.t(),
          updated_at: DateTime.t()
        }

  @enforce_keys [:id, :created_at, :updated_at]
  defstruct [
    :id,
    :created_at,
    :updated_at,
    :provider,
    :model,
    :reasoning_effort,
    version: 1,
    entries: []
  ]

  @spec new(String.t(), keyword()) :: t()
  def new(id, opts \\ []) when is_binary(id) and is_list(opts) do
    timestamp = Keyword.get(opts, :timestamp, DateTime.utc_now())

    %__MODULE__{
      id: id,
      provider: Keyword.get(opts, :provider),
      model: Keyword.get(opts, :model),
      reasoning_effort: Keyword.get(opts, :reasoning_effort),
      created_at: timestamp,
      updated_at: timestamp
    }
  end

  @spec to_llm_messages(t()) :: [Message.t()]
  def to_llm_messages(%__MODULE__{} = session) do
    session.entries
    |> Enum.flat_map(fn
      %Entry{kind: :user, payload: %User{} = message} -> [message]
      %Entry{kind: :assistant, payload: %Assistant{} = message} -> [message]
      %Entry{kind: :tool_result, payload: %ToolResult{} = message} -> [message]
      _ -> []
    end)
  end

  @spec append_messages(t(), [Message.t()], keyword()) :: {t(), [Entry.t()]}
  def append_messages(%__MODULE__{} = session, messages, opts \\ []) when is_list(messages) do
    timestamp = Keyword.get(opts, :timestamp, DateTime.utc_now())
    first_seq = next_seq(session)

    entries =
      messages
      |> Enum.with_index(first_seq)
      |> Enum.map(fn {message, seq} ->
        Entry.from_message(message, seq, timestamp: timestamp)
      end)

    {
      %{session | entries: session.entries ++ entries, updated_at: timestamp},
      entries
    }
  end

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

  defp next_seq(%__MODULE__{entries: []}), do: 0

  defp next_seq(%__MODULE__{entries: entries}) do
    entries
    |> List.last()
    |> Map.fetch!(:seq)
    |> Kernel.+(1)
  end

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
