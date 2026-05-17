defmodule Pado.Agent.Session.Entry do
  alias Pado.Agent.Session.{CompactionSummary, Error, ModelChange}
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
end
