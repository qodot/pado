defmodule Pado.LLMRouter.Catalog.OpenAICodex do
  @moduledoc """
  ChatGPT 계정으로 `/codex/responses` 엔드포인트에서 호출 가능한 모델 목록.

  2026-04 기준 ChatGPT Pro 계정으로 직접 프로빙한 결과만 담는다
  (scripts/codex_probe.sh). 프로바이더 측 가용 모델은 자주 바뀌므로
  이 목록은 정기적으로 갱신해야 한다.

  ## 실측 요약

      id                    ctx   out   reasoning  $in/M  $out/M  cache
      gpt-5.2            272000 128000  yes         1.75   14.00  0.175
      gpt-5.3-codex      272000 128000  yes         1.75   14.00  0.175
      gpt-5.3-codex-spark 128000 128000 yes         0.00    0.00  0.000
      gpt-5.4            272000 128000  yes         2.50   15.00  0.250
      gpt-5.4-mini       272000 128000  yes         0.75    4.50  0.075

  ## 참고

    * 가격은 OpenAI API 기준 단가다. ChatGPT 구독자에게는 별도 청구되지
      않을 가능성이 크지만(추측), 사용량 기록·예산 경보용으로 여전히 유용.
    * 위 모든 모델이 `reasoning: true`지만, 기본 reasoning effort에서는
      `gpt-5.3-codex-spark`만 실제로 reasoning 토큰을 생성했다.
    * 구세대(gpt-5.1, gpt-5.1-codex-*, gpt-5.2-codex-*)는 ChatGPT 계정에서
      차단되어 있다.
  """

  alias Pado.LLMRouter.Model

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

  @doc "가용 모델 전체 리스트."
  @spec all() :: [Model.t()]
  def all, do: Map.values(@models)

  @doc "id로 모델 조회. 없으면 `nil`."
  @spec get(String.t()) :: Model.t() | nil
  def get(id) when is_binary(id), do: Map.get(@models, id)

  @doc "가용 모델 id 목록."
  @spec ids() :: [String.t()]
  def ids, do: Map.keys(@models)

  @doc "기본 모델 (빠르고 저렴한 `gpt-5.4-mini`)."
  @spec default() :: Model.t()
  def default, do: Map.fetch!(@models, @default_id)
end
