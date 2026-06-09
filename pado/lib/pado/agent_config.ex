defmodule Pado.AgentConfig do
  @type provider :: :openai_codex

  @providers [:openai_codex]

  alias Pado.Agent.Job
  alias Pado.AgentConfig.{Harness, LLM}
  alias Pado.AgentConfig.Tools.Bash
  alias Pado.AgentConfig.Tools.Tool
  alias Pado.LLM.Credential.OAuth.Credentials
  alias Pado.LLM.Context, as: LLMContext
  alias Pado.LLM.Model

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

  @spec build(provider(), Credentials.t(), Model.t(), atom() | nil, keyword()) :: t()
  def build(
        provider,
        %Credentials{} = credentials,
        %Model{} = model,
        reasoning_effort,
        opts \\ []
      )
      when provider in @providers do
    %__MODULE__{
      llm: %LLM{
        provider: provider,
        credentials: credentials,
        model: model,
        router: Keyword.get(opts, :router, Pado.LLM),
        opts: llm_opts(reasoning_effort)
      },
      harness: %Harness{tools: Keyword.get(opts, :tools, [Bash.tool()])}
    }
  end

  @spec llm_context(t(), Job.t()) :: LLMContext.t()
  def llm_context(%__MODULE__{} = agent, %Job{} = job) do
    %LLMContext{
      system_prompt: agent.harness.system_prompt,
      messages: Job.llm_messages(job),
      tools: Enum.map(agent.harness.tools, &Tool.as_llm_tool/1)
    }
  end

  defp llm_opts(nil), do: []
  defp llm_opts(reasoning_effort), do: [reasoning_effort: reasoning_effort]
end
