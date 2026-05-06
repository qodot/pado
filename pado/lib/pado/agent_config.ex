defmodule Pado.AgentConfig do
  alias Pado.Agent.Job
  alias Pado.AgentConfig.{Harness, LLM}
  alias Pado.AgentConfig.Tools.Tool
  alias Pado.LLM.Context, as: LLMContext

  @type t :: %__MODULE__{
          name: String.t() | nil,
          description: String.t() | nil,
          llm: LLM.t(),
          harness: Harness.t()
        }

  @enforce_keys [:llm, :harness]
  defstruct [
    :llm,
    :harness,
    name: nil,
    description: nil
  ]

  @spec llm_context(t(), Job.t()) :: LLMContext.t()
  def llm_context(%__MODULE__{} = agent, %Job{} = job) do
    %LLMContext{
      system_prompt: agent.harness.system_prompt,
      messages: Job.llm_messages(job),
      tools: Enum.map(agent.harness.tools, &Tool.as_llm_tool/1)
    }
  end
end
