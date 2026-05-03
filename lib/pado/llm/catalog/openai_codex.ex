defmodule Pado.LLM.Catalog.OpenAICodex do
  alias Pado.LLM.Model

  @base_url "https://chatgpt.com/backend-api"
  @provider :openai_codex

  @models %{
    "gpt-5.2" => %Model{
      id: "gpt-5.2",
      name: "GPT-5.2",
      provider: @provider,
      base_url: @base_url,
      context_window: 272_000,
      max_tokens: 128_000,
      supports_tools: true,
      supports_reasoning: true,
      supports_vision: true,
      cost: %{input: 1.75, output: 14.0, cache_read: 0.175, cache_write: 0.0}
    },
    "gpt-5.3-codex" => %Model{
      id: "gpt-5.3-codex",
      name: "GPT-5.3 Codex",
      provider: @provider,
      base_url: @base_url,
      context_window: 272_000,
      max_tokens: 128_000,
      supports_tools: true,
      supports_reasoning: true,
      supports_vision: true,
      cost: %{input: 1.75, output: 14.0, cache_read: 0.175, cache_write: 0.0}
    },
    "gpt-5.3-codex-spark" => %Model{
      id: "gpt-5.3-codex-spark",
      name: "GPT-5.3 Codex Spark",
      provider: @provider,
      base_url: @base_url,
      context_window: 128_000,
      max_tokens: 128_000,
      supports_tools: true,
      supports_reasoning: true,
      supports_vision: true,
      cost: %{input: 0.0, output: 0.0, cache_read: 0.0, cache_write: 0.0}
    },
    "gpt-5.4" => %Model{
      id: "gpt-5.4",
      name: "GPT-5.4",
      provider: @provider,
      base_url: @base_url,
      context_window: 272_000,
      max_tokens: 128_000,
      supports_tools: true,
      supports_reasoning: true,
      supports_vision: true,
      cost: %{input: 2.5, output: 15.0, cache_read: 0.25, cache_write: 0.0}
    },
    "gpt-5.4-mini" => %Model{
      id: "gpt-5.4-mini",
      name: "GPT-5.4 Mini",
      provider: @provider,
      base_url: @base_url,
      context_window: 272_000,
      max_tokens: 128_000,
      supports_tools: true,
      supports_reasoning: true,
      supports_vision: true,
      cost: %{input: 0.75, output: 4.5, cache_read: 0.075, cache_write: 0.0}
    }
  }

  @default_id "gpt-5.4-mini"

  def all, do: Map.values(@models)

  def get(id) when is_binary(id), do: Map.get(@models, id)

  def ids, do: Map.keys(@models)

  def default, do: Map.fetch!(@models, @default_id)
end
