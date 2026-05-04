defmodule Pado.LLM.Catalog.OpenAICodex do
  alias Pado.LLM.Model

  @base_url "https://chatgpt.com/backend-api"
  @provider :openai_codex

  # 모델 목록과 메타데이터는 codex 클라이언트가 번들하는
  # `codex-rs/models-manager/models.json` fixture를 기준으로 맞춘다.
  # cost는 해당 fixture에 없어 일단 0으로 둔다.

  @models %{
    "gpt-5.5" => %Model{
      id: "gpt-5.5",
      name: "GPT-5.5",
      provider: @provider,
      base_url: @base_url,
      context_window: 272_000,
      max_tokens: 128_000,
      supports_tools: true,
      supports_reasoning: true,
      supports_vision: true,
      cost: %{input: 0.0, output: 0.0, cache_read: 0.0, cache_write: 0.0}
    },
    "gpt-5.4" => %Model{
      id: "gpt-5.4",
      name: "gpt-5.4",
      provider: @provider,
      base_url: @base_url,
      context_window: 272_000,
      max_tokens: 128_000,
      supports_tools: true,
      supports_reasoning: true,
      supports_vision: true,
      cost: %{input: 0.0, output: 0.0, cache_read: 0.0, cache_write: 0.0}
    },
    "gpt-5.4-mini" => %Model{
      id: "gpt-5.4-mini",
      name: "GPT-5.4-Mini",
      provider: @provider,
      base_url: @base_url,
      context_window: 272_000,
      max_tokens: 128_000,
      supports_tools: true,
      supports_reasoning: true,
      supports_vision: true,
      cost: %{input: 0.0, output: 0.0, cache_read: 0.0, cache_write: 0.0}
    },
    "gpt-5.3-codex" => %Model{
      id: "gpt-5.3-codex",
      name: "gpt-5.3-codex",
      provider: @provider,
      base_url: @base_url,
      context_window: 272_000,
      max_tokens: 128_000,
      supports_tools: true,
      supports_reasoning: true,
      supports_vision: true,
      cost: %{input: 0.0, output: 0.0, cache_read: 0.0, cache_write: 0.0}
    },
    "gpt-5.2" => %Model{
      id: "gpt-5.2",
      name: "gpt-5.2",
      provider: @provider,
      base_url: @base_url,
      context_window: 272_000,
      max_tokens: 128_000,
      supports_tools: true,
      supports_reasoning: true,
      supports_vision: true,
      cost: %{input: 0.0, output: 0.0, cache_read: 0.0, cache_write: 0.0}
    }
  }

  @default_id "gpt-5.4-mini"

  def all, do: Map.values(@models)

  def get(id) when is_binary(id), do: Map.get(@models, id)

  def ids, do: Map.keys(@models)

  def default, do: Map.fetch!(@models, @default_id)
end
