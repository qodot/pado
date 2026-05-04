defmodule Pado.Agent.Tool do
  alias Pado.LLM.Tool, as: RouterTool

  @type execute_fun :: (map(), map() -> term())

  @type t :: %__MODULE__{
          schema: RouterTool.t(),
          execute: execute_fun()
        }

  @enforce_keys [:schema, :execute]
  defstruct [:schema, :execute]
end
