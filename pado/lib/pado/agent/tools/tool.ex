defmodule Pado.Agent.Tools.Tool do
  alias Pado.LLM.Tool, as: RouterTool

  @type execute_fun :: (map(), map() -> term())

  @type t :: %__MODULE__{
          schema: RouterTool.t(),
          execute: execute_fun()
        }

  @enforce_keys [:schema, :execute]
  defstruct [:schema, :execute]

  @spec as_llm_tool(t()) :: RouterTool.t()
  def as_llm_tool(%__MODULE__{schema: schema}), do: schema
end
