defmodule Pado.Agent.Tool do
  alias Pado.LLM.Tool, as: RouterTool

  @type execute_fun :: (map(), map() -> term())

  @type t :: %__MODULE__{
          definition: RouterTool.t(),
          execute: execute_fun()
        }

  @enforce_keys [:definition, :execute]
  defstruct [:definition, :execute]
end
