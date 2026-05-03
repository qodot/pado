defmodule Pado.Agent do
  alias Pado.Agent.Tool

  @type t :: %__MODULE__{
          router: module(),
          credential_provider: atom(),
          tools: [Tool.t()]
        }

  @enforce_keys [:credential_provider]
  defstruct [
    :credential_provider,
    router: Application.compile_env(:pado, :router, Pado.LLM),
    tools: []
  ]
end
