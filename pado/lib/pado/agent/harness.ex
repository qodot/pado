defmodule Pado.Agent.Harness do
  alias Pado.Agent.Tools.Tool

  @type t :: %__MODULE__{
          system_prompt: String.t() | nil,
          tools: [Tool.t()]
        }

  defstruct system_prompt: nil, tools: []
end
