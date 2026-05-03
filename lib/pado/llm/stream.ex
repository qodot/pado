defmodule Pado.LLM.Stream do
  @type t :: %__MODULE__{
          events: Enumerable.t(),
          cancel: (-> :ok)
        }

  @enforce_keys [:events, :cancel]
  defstruct [:events, :cancel]
end

defimpl Enumerable, for: Pado.LLM.Stream do
  def count(_stream), do: {:error, __MODULE__}
  def member?(_stream, _value), do: {:error, __MODULE__}
  def slice(_stream), do: {:error, __MODULE__}

  def reduce(%Pado.LLM.Stream{events: events}, acc, fun) do
    Enumerable.reduce(events, acc, fun)
  end
end
