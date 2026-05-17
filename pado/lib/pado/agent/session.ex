defmodule Pado.Agent.Session do
  alias Pado.Agent.Session.Entry

  @type t :: %__MODULE__{
          id: String.t(),
          version: pos_integer(),
          entries: [Entry.t()],
          created_at: DateTime.t(),
          updated_at: DateTime.t()
        }

  @enforce_keys [:id, :created_at, :updated_at]
  defstruct [
    :id,
    :created_at,
    :updated_at,
    version: 1,
    entries: []
  ]
end
