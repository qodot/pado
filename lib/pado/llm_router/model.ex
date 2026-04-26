defmodule Pado.LLMRouter.Model do
  @moduledoc """
  LLM 모델 메타데이터.

  `Pado.LLMRouter.stream/3` 등에 넘겨 어떤 모델로 어떤 엔드포인트에
  요청을 보낼지 결정한다. 프로바이더 어댑터는 이 구조체의 `:provider`를
  보고 자기 호출이 맞는지 확인한다.

  ## 필드

    * `:id` — 모델 식별자. 프로바이더 API에 그대로 보내는 문자열
      (예: `"gpt-5.1"`, `"claude-opus-4-5"`).
    * `:name` — 사람이 읽는 이름.
    * `:provider` — 크레덴셜과 OAuth 프로바이더 키. `%Credentials{provider: …}`와 매칭.
    * `:base_url` — 프로바이더 API 기본 URL.
    * `:context_window` — 허용 최대 입력 토큰.
    * `:max_tokens` — 응답에서 허용되는 최대 출력 토큰.
    * `:supports_tools` — 도구(tool use) 호출 지원 여부.
    * `:supports_reasoning` — 내부 reasoning/thinking 토큰 지원 여부.
    * `:supports_vision` — 이미지 입력 지원 여부.
    * `:cost` — 1M 토큰당 USD 단가.
    * `:headers` — 이 모델 호출 시 항상 붙는 기본 헤더.
  """

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

  @doc """
  주어진 usage(토큰 수)와 이 모델의 단가로 USD 금액을 계산한다.

  단가는 1,000,000 토큰 기준이며, 결과는 `Pado.LLMRouter.Usage.cost/0` 맵 형식.
  """
  @spec calculate_cost(t, Pado.LLMRouter.Usage.t()) :: Pado.LLMRouter.Usage.cost()
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
