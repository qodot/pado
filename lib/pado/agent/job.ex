defmodule Pado.Agent.Job do
  alias Pado.Agent
  alias Pado.Agent.Turn
  alias Pado.LLM.Context, as: LLMContext
  alias Pado.LLM.Message, as: LLMMessage
  alias Pado.LLM.Tool, as: LLMTool

  @type t :: %__MODULE__{
          agent: Agent.t(),
          messages: [LLMMessage.t()],
          session_id: String.t(),
          turns: [Turn.t()],
          job_id: String.t() | nil
        }

  @enforce_keys [:agent, :messages, :session_id]
  defstruct [
    :agent,
    :messages,
    :session_id,
    turns: [],
    job_id: nil
  ]

  @spec llm_messages(t()) :: [LLMMessage.t()]
  def llm_messages(%__MODULE__{} = job) do
    job.messages ++ Enum.flat_map(job.turns, &Turn.as_llm_messages/1)
  end

  @spec llm_tools(t()) :: [LLMTool.t()]
  def llm_tools(%__MODULE__{} = job) do
    Enum.map(job.agent.harness.tools, & &1.schema)
  end

  @spec llm_context(t()) :: LLMContext.t()
  def llm_context(%__MODULE__{} = job) do
    %LLMContext{
      system_prompt: job.agent.harness.system_prompt,
      messages: llm_messages(job),
      tools: llm_tools(job)
    }
  end
end
