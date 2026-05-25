defmodule Pado.Agent.Session.Entry do
  alias Pado.Agent.Session.{CompactionSummary, Error, ModelChange}
  alias Pado.LLM.Message
  alias Pado.LLM.Message.{Assistant, ToolResult, User}
  alias Pado.LLM.Usage

  @type kind ::
          :user
          | :assistant
          | :tool_result
          | :compaction_summary
          | :model_change
          | :error

  @type payload ::
          User.t()
          | Assistant.t()
          | ToolResult.t()
          | CompactionSummary.t()
          | ModelChange.t()
          | Error.t()

  @type t :: %__MODULE__{
          id: String.t(),
          seq: non_neg_integer(),
          kind: kind(),
          payload: payload(),
          refs: map(),
          timestamp: DateTime.t()
        }

  @enforce_keys [:id, :seq, :kind, :payload, :timestamp]
  defstruct [
    :id,
    :seq,
    :kind,
    :payload,
    :timestamp,
    refs: %{}
  ]

  @spec from_message(Message.t(), non_neg_integer(), keyword()) :: t()
  def from_message(message, seq, opts \\ [])

  def from_message(%User{} = message, seq, opts) do
    build(:user, message, seq, opts)
  end

  def from_message(%Assistant{} = message, seq, opts) do
    refs =
      message.content
      |> Enum.flat_map(fn
        {:tool_call, %{id: id}} -> [id]
        _ -> []
      end)
      |> case do
        [] -> %{}
        ids -> %{"tool_call_ids" => ids}
      end

    build(:assistant, message, seq, Keyword.put_new(opts, :refs, refs))
  end

  def from_message(%ToolResult{} = message, seq, opts) do
    refs = %{"tool_call_id" => message.tool_call_id}
    build(:tool_result, message, seq, Keyword.put_new(opts, :refs, refs))
  end

  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{} = entry) do
    %{
      "type" => "entry",
      "id" => entry.id,
      "seq" => entry.seq,
      "kind" => Atom.to_string(entry.kind),
      "payload" => encode_payload(entry.kind, entry.payload),
      "refs" => entry.refs,
      "timestamp" => encode_datetime(entry.timestamp)
    }
  end

  @spec from_map(map()) :: {:ok, t()} | {:error, term()}
  def from_map(%{"type" => "entry"} = map) do
    with {:ok, kind} <- decode_kind(map["kind"]),
         {:ok, timestamp} <- decode_datetime(map["timestamp"]),
         {:ok, payload} <- decode_payload(kind, map["payload"]) do
      {:ok,
       %__MODULE__{
         id: map["id"],
         seq: map["seq"],
         kind: kind,
         payload: payload,
         refs: map["refs"] || %{},
         timestamp: timestamp
       }}
    end
  end

  def from_map(map), do: {:error, {:invalid_entry_map, map}}

  defp build(kind, payload, seq, opts) do
    %__MODULE__{
      id: Keyword.get(opts, :id, new_id()),
      seq: seq,
      kind: kind,
      payload: payload,
      refs: Keyword.get(opts, :refs, %{}),
      timestamp: Keyword.get(opts, :timestamp, DateTime.utc_now())
    }
  end

  defp new_id do
    "entry-" <> Integer.to_string(System.unique_integer([:positive, :monotonic]))
  end

  defp encode_payload(:user, %User{} = message) do
    %{
      "content" => encode_content(message.content),
      "timestamp" => encode_datetime(message.timestamp)
    }
  end

  defp encode_payload(:assistant, %Assistant{} = message) do
    %{
      "content" => encode_content(message.content),
      "stop_reason" => encode_atom(message.stop_reason),
      "error_message" => message.error_message,
      "usage" => encode_usage(message.usage),
      "provider" => encode_atom(message.provider),
      "model" => message.model,
      "timestamp" => encode_datetime(message.timestamp)
    }
  end

  defp encode_payload(:tool_result, %ToolResult{} = result) do
    %{
      "tool_call_id" => result.tool_call_id,
      "tool_name" => result.tool_name,
      "content" => encode_content(result.content),
      "is_error" => result.is_error,
      "timestamp" => encode_datetime(result.timestamp)
    }
  end

  defp encode_payload(:compaction_summary, %CompactionSummary{} = summary) do
    %{
      "summary" => summary.summary,
      "first_kept_seq" => summary.first_kept_seq,
      "tokens_before" => summary.tokens_before
    }
  end

  defp encode_payload(:model_change, %ModelChange{} = change) do
    %{
      "provider" => encode_atom(change.provider),
      "from" => change.from,
      "to" => change.to,
      "reasoning_effort" => encode_atom(change.reasoning_effort)
    }
  end

  defp encode_payload(:error, %Error{} = error) do
    %{
      "message" => error.message,
      "reason" => encode_reason(error.reason)
    }
  end

  defp encode_content(content) when is_binary(content), do: content
  defp encode_content(parts) when is_list(parts), do: Enum.map(parts, &encode_content_part/1)

  defp encode_content_part({:text, text}), do: %{"type" => "text", "text" => text}
  defp encode_content_part({:thinking, text}), do: %{"type" => "thinking", "text" => text}

  defp encode_content_part({:image, %{media_type: media_type, data: data}}) do
    %{"type" => "image", "media_type" => media_type, "data" => data}
  end

  defp encode_content_part({:tool_call, %{id: id, name: name, args: args}}) do
    %{"type" => "tool_call", "id" => id, "name" => name, "args" => args}
  end

  defp encode_usage(nil), do: nil

  defp encode_usage(%Usage{} = usage) do
    %{
      "input" => usage.input,
      "output" => usage.output,
      "cache_read" => usage.cache_read,
      "cache_write" => usage.cache_write,
      "total_tokens" => usage.total_tokens,
      "cost" => %{
        "input" => usage.cost.input,
        "output" => usage.cost.output,
        "cache_read" => usage.cost.cache_read,
        "cache_write" => usage.cost.cache_write,
        "total" => usage.cost.total
      }
    }
  end

  defp encode_datetime(nil), do: nil
  defp encode_datetime(%DateTime{} = datetime), do: DateTime.to_iso8601(datetime)

  defp encode_atom(nil), do: nil
  defp encode_atom(atom) when is_atom(atom), do: Atom.to_string(atom)

  defp encode_reason(reason) when is_binary(reason), do: reason
  defp encode_reason(reason), do: inspect(reason)

  defp decode_kind("user"), do: {:ok, :user}
  defp decode_kind("assistant"), do: {:ok, :assistant}
  defp decode_kind("tool_result"), do: {:ok, :tool_result}
  defp decode_kind("compaction_summary"), do: {:ok, :compaction_summary}
  defp decode_kind("model_change"), do: {:ok, :model_change}
  defp decode_kind("error"), do: {:ok, :error}
  defp decode_kind(kind), do: {:error, {:unknown_kind, kind}}

  defp decode_payload(:user, map) when is_map(map) do
    with {:ok, content} <- decode_content(map["content"]),
         {:ok, timestamp} <- decode_datetime(map["timestamp"]) do
      {:ok, %User{content: content, timestamp: timestamp}}
    end
  end

  defp decode_payload(:assistant, map) when is_map(map) do
    with {:ok, content} <- decode_content(map["content"]),
         {:ok, stop_reason} <- decode_stop_reason(map["stop_reason"]),
         {:ok, usage} <- decode_usage(map["usage"]),
         {:ok, provider} <- decode_existing_atom(map["provider"]),
         {:ok, timestamp} <- decode_datetime(map["timestamp"]) do
      {:ok,
       %Assistant{
         content: content,
         stop_reason: stop_reason,
         error_message: map["error_message"],
         usage: usage,
         provider: provider,
         model: map["model"],
         timestamp: timestamp
       }}
    end
  end

  defp decode_payload(:tool_result, map) when is_map(map) do
    with {:ok, content} <- decode_content(map["content"]),
         {:ok, timestamp} <- decode_datetime(map["timestamp"]) do
      {:ok,
       %ToolResult{
         tool_call_id: map["tool_call_id"],
         tool_name: map["tool_name"],
         content: content,
         is_error: map["is_error"] || false,
         timestamp: timestamp
       }}
    end
  end

  defp decode_payload(:compaction_summary, map) when is_map(map) do
    {:ok,
     %CompactionSummary{
       summary: map["summary"],
       first_kept_seq: map["first_kept_seq"],
       tokens_before: map["tokens_before"]
     }}
  end

  defp decode_payload(:model_change, map) when is_map(map) do
    with {:ok, provider} <- decode_existing_atom(map["provider"]),
         {:ok, reasoning_effort} <- decode_existing_atom(map["reasoning_effort"]) do
      {:ok,
       %ModelChange{
         provider: provider,
         from: map["from"],
         to: map["to"],
         reasoning_effort: reasoning_effort
       }}
    end
  end

  defp decode_payload(:error, map) when is_map(map) do
    {:ok, %Error{message: map["message"], reason: map["reason"]}}
  end

  defp decode_payload(_kind, payload), do: {:error, {:invalid_payload, payload}}

  defp decode_content(content) when is_binary(content), do: {:ok, content}

  defp decode_content(parts) when is_list(parts) do
    parts
    |> Enum.reduce_while({:ok, []}, fn part, {:ok, acc} ->
      case decode_content_part(part) do
        {:ok, decoded} -> {:cont, {:ok, [decoded | acc]}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, decoded} -> {:ok, Enum.reverse(decoded)}
      error -> error
    end
  end

  defp decode_content(content), do: {:error, {:invalid_content, content}}

  defp decode_content_part(%{"type" => "text", "text" => text}), do: {:ok, {:text, text}}

  defp decode_content_part(%{"type" => "thinking", "text" => text}) do
    {:ok, {:thinking, text}}
  end

  defp decode_content_part(%{"type" => "image", "media_type" => media_type, "data" => data}) do
    {:ok, {:image, %{media_type: media_type, data: data}}}
  end

  defp decode_content_part(%{
         "type" => "tool_call",
         "id" => id,
         "name" => name,
         "args" => args
       }) do
    {:ok, {:tool_call, %{id: id, name: name, args: args || %{}}}}
  end

  defp decode_content_part(part), do: {:error, {:unknown_content_part, part}}

  defp decode_usage(nil), do: {:ok, nil}

  defp decode_usage(map) when is_map(map) do
    cost = map["cost"] || %{}

    {:ok,
     %Usage{
       input: map["input"] || 0,
       output: map["output"] || 0,
       cache_read: map["cache_read"] || 0,
       cache_write: map["cache_write"] || 0,
       total_tokens: map["total_tokens"] || 0,
       cost: %{
         input: cost["input"] || 0.0,
         output: cost["output"] || 0.0,
         cache_read: cost["cache_read"] || 0.0,
         cache_write: cost["cache_write"] || 0.0,
         total: cost["total"] || 0.0
       }
     }}
  end

  defp decode_usage(usage), do: {:error, {:invalid_usage, usage}}

  defp decode_datetime(nil), do: {:ok, nil}

  defp decode_datetime(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, datetime, _offset} -> {:ok, datetime}
      {:error, reason} -> {:error, {:invalid_datetime, value, reason}}
    end
  end

  defp decode_datetime(value), do: {:error, {:invalid_datetime, value}}

  defp decode_stop_reason(nil), do: {:ok, nil}
  defp decode_stop_reason("stop"), do: {:ok, :stop}
  defp decode_stop_reason("length"), do: {:ok, :length}
  defp decode_stop_reason("tool_use"), do: {:ok, :tool_use}
  defp decode_stop_reason("aborted"), do: {:ok, :aborted}
  defp decode_stop_reason("error"), do: {:ok, :error}
  defp decode_stop_reason(reason), do: {:error, {:unknown_stop_reason, reason}}

  defp decode_existing_atom(nil), do: {:ok, nil}
  defp decode_existing_atom("openai_codex"), do: {:ok, :openai_codex}

  defp decode_existing_atom(value) when is_binary(value) do
    {:ok, String.to_existing_atom(value)}
  rescue
    ArgumentError -> {:error, {:unknown_atom, value}}
  end

  defp decode_existing_atom(value), do: {:error, {:invalid_atom, value}}
end
