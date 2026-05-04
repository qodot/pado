defmodule Pado.LLM.Tool do
  @type json_schema :: map

  @type t :: %__MODULE__{
          name: String.t(),
          description: String.t(),
          parameters: json_schema,
          metadata: map
        }

  @enforce_keys [:name, :description, :parameters]
  defstruct [:name, :description, :parameters, metadata: %{}]

  def new(name, description, parameters, opts \\ []) do
    %__MODULE__{
      name: name,
      description: description,
      parameters: parameters,
      metadata: Keyword.get(opts, :metadata, %{})
    }
  end
end
