defmodule Pado.LLM.Catalog.ZAI do
  alias Pado.LLM.Model

  @base_url "https://api.z.ai/api/paas/v4"
  @provider :z_ai
  @zero_cost %{input: 0.0, output: 0.0, cache_read: 0.0, cache_write: 0.0}

  @models %{
    "glm-5.2" => %Model{
      id: "glm-5.2",
      name: "GLM-5.2",
      provider: @provider,
      base_url: @base_url,
      context_window: 1_000_000,
      max_tokens: 128_000,
      supports_tools: true,
      supports_reasoning: true,
      supports_vision: false,
      cost: @zero_cost
    },
    "glm-5.1" => %Model{
      id: "glm-5.1",
      name: "GLM-5.1",
      provider: @provider,
      base_url: @base_url,
      context_window: 1_000_000,
      max_tokens: 128_000,
      supports_tools: true,
      supports_reasoning: true,
      supports_vision: false,
      cost: @zero_cost
    },
    "glm-5" => %Model{
      id: "glm-5",
      name: "GLM-5",
      provider: @provider,
      base_url: @base_url,
      context_window: 200_000,
      max_tokens: 128_000,
      supports_tools: true,
      supports_reasoning: true,
      supports_vision: false,
      cost: @zero_cost
    },
    "glm-4.7" => %Model{
      id: "glm-4.7",
      name: "GLM-4.7",
      provider: @provider,
      base_url: @base_url,
      context_window: 200_000,
      max_tokens: 128_000,
      supports_tools: true,
      supports_reasoning: true,
      supports_vision: false,
      cost: @zero_cost
    }
  }

  @default_id "glm-5.2"

  def all, do: Map.values(@models)

  def get(id) when is_binary(id), do: Map.get(@models, id)

  def ids, do: Map.keys(@models)

  def default, do: Map.fetch!(@models, @default_id)
end
