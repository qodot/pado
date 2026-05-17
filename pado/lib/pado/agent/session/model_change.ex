defmodule Pado.Agent.Session.ModelChange do
  @type t :: %__MODULE__{
          provider: atom(),
          from: String.t() | nil,
          to: String.t()
        }

  @enforce_keys [:provider, :to]
  defstruct [:provider, :from, :to]
end
