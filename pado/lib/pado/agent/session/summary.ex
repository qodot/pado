defmodule Pado.Agent.Session.Summary do
  @type t :: %__MODULE__{
          id: String.t(),
          version: pos_integer(),
          created_at: DateTime.t(),
          updated_at: DateTime.t()
        }

  @enforce_keys [:id, :version, :created_at, :updated_at]
  defstruct [:id, :version, :created_at, :updated_at]
end
