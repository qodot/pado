defmodule Pado.Agent.Job do
  alias Pado.Agent.Turn
  alias Pado.LLM.Message, as: LLMMessage

  @type t :: %__MODULE__{
          messages: [LLMMessage.t()],
          session_id: String.t(),
          turns: [Turn.t()],
          job_id: String.t() | nil,
          max_turns: pos_integer()
        }

  @enforce_keys [:messages, :session_id]
  defstruct [
    :messages,
    :session_id,
    turns: [],
    job_id: nil,
    max_turns: 10
  ]

  @spec llm_messages(t()) :: [LLMMessage.t()]
  def llm_messages(%__MODULE__{} = job) do
    job.messages ++ Enum.flat_map(job.turns, &Turn.as_llm_messages/1)
  end
end
