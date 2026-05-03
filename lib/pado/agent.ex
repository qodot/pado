defmodule Pado.Agent do
  alias Pado.Agent.{Harness, LLM}

  @type t :: %__MODULE__{
          name: String.t() | nil,
          description: String.t() | nil,
          max_turns: pos_integer(),
          llm: LLM.t(),
          harness: Harness.t()
        }

  @enforce_keys [:llm, :harness]
  defstruct [
    :llm,
    :harness,
    name: nil,
    description: nil,
    max_turns: 10
  ]
end
