defmodule Pado.Agent do
  alias Pado.Agent.Tool

  @type t :: %__MODULE__{
          name: String.t() | nil,
          description: String.t() | nil,
          system_prompt: String.t() | nil,
          router: module(),
          credential_provider: atom(),
          tools: [Tool.t()]
        }

  @enforce_keys [:credential_provider]
  defstruct [
    :credential_provider,
    name: nil,
    description: nil,
    system_prompt: nil,
    router: Application.compile_env(:pado, :router, Pado.LLM),
    tools: []
  ]
end
