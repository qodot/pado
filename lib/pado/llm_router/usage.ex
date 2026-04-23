defmodule Pado.LLMRouter.Usage do
  @moduledoc """
  LLM 호출 한 번에 대한 토큰 사용량과 금액.

  프로바이더마다 토큰 분류가 약간씩 다르지만 Pado는 다음 네 종류로 정규화한다.

    * `:input` — 프롬프트에 들어간 토큰
    * `:output` — 모델이 생성한 토큰
    * `:cache_read` — 프로바이더 측 프롬프트 캐시에서 재사용된 토큰
    * `:cache_write` — 새로 캐시에 기록된 토큰

  `:total_tokens`는 위 네 항목을 합친 값이며, `:cost`는 모델의 단가
  (`Pado.LLMRouter.Model`)에 곱해 산정한 USD 금액이다.

  구조체는 프로바이더 어댑터가 스트리밍 이벤트를 집계해 채우는 것을 가정한다.
  """

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

  @doc "모든 항목이 0인 기본 usage를 반환한다."
  @spec empty() :: t
  def empty, do: %__MODULE__{}

  @doc """
  두 usage를 합산해 새 usage를 돌려준다. 같은 요청 안에서 여러 스트림
  청크를 누적할 때 쓴다.
  """
  @spec add(t, t) :: t
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
