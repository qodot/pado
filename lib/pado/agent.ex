defmodule Pado.Agent do
  alias Pado.Agent.Tool
  alias Pado.LLM.Model

  @type t :: %__MODULE__{
          name: String.t() | nil,
          description: String.t() | nil,
          system_prompt: String.t() | nil,
          model: Model.t(),
          router: module(),
          credential_provider: atom(),
          tools: [Tool.t()],
          llm_opts: keyword(),
          max_turns: pos_integer()
        }

  @enforce_keys [:credential_provider, :model]
  defstruct [
    :credential_provider,
    :model,
    name: nil,
    description: nil,
    system_prompt: nil,
    router: Application.compile_env(:pado, :router, Pado.LLM),
    tools: [],
    llm_opts: [],
    max_turns: 10
  ]
end
