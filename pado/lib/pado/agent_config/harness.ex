defmodule Pado.AgentConfig.Harness do
  alias Pado.AgentConfig.Tools.Tool

  @type t :: %__MODULE__{
          system_prompt: String.t() | nil,
          tools: [Tool.t()]
        }

  defstruct system_prompt: nil, tools: []
end
