defmodule Pado.Agent.Session.Error do
  @type t :: %__MODULE__{
          message: String.t(),
          reason: term()
        }

  @enforce_keys [:message, :reason]
  defstruct [:message, :reason]
end
