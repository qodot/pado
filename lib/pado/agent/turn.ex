defmodule Pado.Agent.Turn do
  alias Pado.LLMRouter.Message
  alias Pado.LLMRouter.Message.{Assistant, ToolResult, User}
  alias Pado.LLMRouter.Usage

  @type t :: %__MODULE__{
          index: pos_integer(),
          injected: [User.t()],
          assistant: Assistant.t(),
          tool_results: [ToolResult.t()],
          usage: Usage.t() | nil
        }

  @enforce_keys [:index, :assistant]
  defstruct [:index, :assistant, injected: [], tool_results: [], usage: nil]

  @spec flatten(t()) :: [Message.t()]
  def flatten(%__MODULE__{} = _turn) do
    raise "not implemented"
  end
end
