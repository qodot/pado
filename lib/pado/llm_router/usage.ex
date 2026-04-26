defmodule Pado.LLMRouter.Usage do
  @type cost :: %{
          input: float,
          output: float,
          cache_read: float,
          cache_write: float,
          total: float
        }

  @type t :: %__MODULE__{
          input: non_neg_integer,
          output: non_neg_integer,
          cache_read: non_neg_integer,
          cache_write: non_neg_integer,
          total_tokens: non_neg_integer,
          cost: cost
        }

  defstruct input: 0,
            output: 0,
            cache_read: 0,
            cache_write: 0,
            total_tokens: 0,
            cost: %{
              input: 0.0,
              output: 0.0,
              cache_read: 0.0,
              cache_write: 0.0,
              total: 0.0
            }

  def empty, do: %__MODULE__{}

  def add(%__MODULE__{} = a, %__MODULE__{} = b) do
    %__MODULE__{
      input: a.input + b.input,
      output: a.output + b.output,
      cache_read: a.cache_read + b.cache_read,
      cache_write: a.cache_write + b.cache_write,
      total_tokens: a.total_tokens + b.total_tokens,
      cost: %{
        input: a.cost.input + b.cost.input,
        output: a.cost.output + b.cost.output,
        cache_read: a.cost.cache_read + b.cost.cache_read,
        cache_write: a.cost.cache_write + b.cost.cache_write,
        total: a.cost.total + b.cost.total
      }
    }
  end
end
