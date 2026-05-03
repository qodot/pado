defmodule Pado.Agent.Event do
  alias Pado.Agent.Turn
  alias Pado.LLM
  alias Pado.LLM.Message
  alias Pado.LLM.Message.{Assistant, ToolResult}

  @type job_id :: String.t()
  @type turn_index :: pos_integer()
  @type status :: :done | :max_turns | :error

  @type t ::
          {:job_start, %{job_id: job_id()}}
          | {:job_end,
             %{
               job_id: job_id(),
               status: status(),
               reason: term() | nil,
               turns: [Turn.t()]
             }}
          | {:turn_start, %{job_id: job_id(), turn_index: turn_index()}}
          | {:turn_end, %{job_id: job_id(), turn: Turn.t()}}
          | {:message_start, %{job_id: job_id(), message: Message.t()}}
          | {:message_update, %{job_id: job_id(), llm_event: LLM.Event.t()}}
          | {:message_end, %{job_id: job_id(), message: Message.t()}}
          | {:tool_execution_start,
             %{
               job_id: job_id(),
               turn_index: turn_index(),
               tool_call_id: String.t(),
               tool_name: String.t(),
               args: map()
             }}
          | {:tool_execution_end,
             %{
               job_id: job_id(),
               turn_index: turn_index(),
               tool_call_id: String.t(),
               tool_name: String.t(),
               result: ToolResult.t(),
               is_error: boolean()
             }}
          | {:error, %{job_id: job_id(), reason: term(), message: Assistant.t() | nil}}

  @spec terminal?(t()) :: boolean()
  def terminal?({:job_end, _}), do: true
  def terminal?({:error, _}), do: true
  def terminal?(_), do: false
end
