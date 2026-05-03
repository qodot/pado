defmodule Pado.Agent.Job do
  alias Pado.Agent
  alias Pado.Agent.Turn
  alias Pado.LLM.{Context, Message, Model}
  alias Pado.LLM.Tool, as: LLMTool

  @type t :: %__MODULE__{
          agent: Agent.t(),
          model: Model.t(),
          session_id: String.t(),
          context: Context.t(),
          turns: [Turn.t()],
          job_id: String.t() | nil,
          llm_opts: keyword(),
          max_turns: pos_integer()
        }

  @enforce_keys [:agent, :model, :session_id, :context]
  defstruct [
    :agent,
    :model,
    :session_id,
    :context,
    turns: [],
    job_id: nil,
    llm_opts: [],
    max_turns: 10
  ]

  @spec llm_messages(t()) :: [Message.t()]
  def llm_messages(%__MODULE__{} = job) do
    job.context.messages ++ Enum.flat_map(job.turns, &Turn.as_llm_messages/1)
  end

  @spec llm_tools(t()) :: [LLMTool.t()]
  def llm_tools(%__MODULE__{} = job) do
    Enum.map(job.agent.tools, & &1.schema)
  end

  @spec llm_context(t()) :: Context.t()
  def llm_context(%__MODULE__{} = job) do
    %{job.context | messages: llm_messages(job), tools: llm_tools(job)}
  end
end
