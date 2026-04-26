defmodule Pado.LLMRouter.Model do
  @type provider :: atom
  @type cost_table :: %{
          input: float,
          output: float,
          cache_read: float,
          cache_write: float
        }

  @type t :: %__MODULE__{
          id: String.t(),
          name: String.t() | nil,
          provider: provider,
          base_url: String.t() | nil,
          context_window: non_neg_integer,
          max_tokens: non_neg_integer,
          supports_tools: boolean,
          supports_reasoning: boolean,
          supports_vision: boolean,
          cost: cost_table,
          headers: %{optional(String.t()) => String.t()}
        }

  @enforce_keys [:id, :provider]
  defstruct [
    :id,
    :name,
    :provider,
    :base_url,
    context_window: 0,
    max_tokens: 0,
    supports_tools: true,
    supports_reasoning: false,
    supports_vision: false,
    cost: %{input: 0.0, output: 0.0, cache_read: 0.0, cache_write: 0.0},
    headers: %{}
  ]

  def calculate_cost(%__MODULE__{cost: c}, %Pado.LLMRouter.Usage{} = u) do
    input = c.input / 1_000_000 * u.input
    output = c.output / 1_000_000 * u.output
    cache_read = c.cache_read / 1_000_000 * u.cache_read
    cache_write = c.cache_write / 1_000_000 * u.cache_write

    %{
      input: input,
      output: output,
      cache_read: cache_read,
      cache_write: cache_write,
      total: input + output + cache_read + cache_write
    }
  end
end
