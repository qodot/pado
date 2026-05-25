defmodule Pado.Agent.Session.ModelChange do
  @type t :: %__MODULE__{
          provider: atom(),
          from: String.t() | nil,
          to: String.t(),
          reasoning_effort: atom() | nil
        }

  @enforce_keys [:provider, :to]
  defstruct [:provider, :from, :to, :reasoning_effort]
end
