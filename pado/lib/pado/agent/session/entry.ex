defmodule Pado.Agent.Session.Entry do
  alias Pado.Agent.Session.{CompactionSummary, Error, ModelChange}
  alias Pado.LLM.Message
  alias Pado.LLM.Message.{Assistant, ToolResult, User}

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
end
