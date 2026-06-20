defmodule Pado.AgentConfig.Tools.Tool do
  alias Pado.LLM.Tool, as: RouterTool

  @type update_fun :: (term() -> any())
  @type async_fun :: (map(), map(), update_fun() -> Task.t())
  @type abort_fun :: (Task.t() -> any())

  @type t :: %__MODULE__{
          schema: RouterTool.t(),
          async: async_fun(),
          abort: abort_fun()
        }

  @enforce_keys [:schema, :async, :abort]
  defstruct [:schema, :async, :abort]

  @spec as_llm_tool(t()) :: RouterTool.t()
  def as_llm_tool(%__MODULE__{schema: schema}), do: schema
end
