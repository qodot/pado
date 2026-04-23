defmodule Pado.LLMRouter.Adapter do
  @moduledoc """
  LLM 프로바이더 어댑터 behaviour.

  한 어댑터는 하나의 `Pado.LLMRouter.Model`의 `:api` 값에 대응한다.
  예: `:openai_codex_responses` → `Pado.LLMRouter.Providers.OpenAICodex.Responses`.

  OAuth 프로바이더 behaviour(`Pado.LLMRouter.OAuth.Provider`)와는 별개다.
  OAuth 쪽은 인증 발급·갱신만, Adapter는 실제 LLM 호출을 담당한다.
  """

  alias Pado.LLMRouter.{Context, Model}

  @typedoc "스트림 이벤트 Enumerable. 지연 실행된다."
  @type event_stream :: Enumerable.t()

  @typedoc """
  어댑터 호출 옵션. 어댑터별로 받는 키가 다르지만 관용적으로:

    * `:credentials` — `%Pado.LLMRouter.OAuth.Credentials{}` (OAuth 기반)
    * `:api_key` — 문자열 API 키 (API 키 기반)
    * `:session_id` — 프롬프트 캐시 키
    * `:reasoning_effort` — `:off | :minimal | :low | :medium | :high | :xhigh`
    * `:req` — `Req` 옵션 전달(테스트에서 모킹용)
  """
  @type opts :: keyword

  @doc """
  LLM에 요청을 보내고 이벤트 스트림을 돌려준다.

  반환 Enumerable은 `Pado.LLMRouter.Event.t/0` 튜플을 방출하며, 종료
  이벤트(`:done` 또는 `:error`)를 만나면 더 이상 방출하지 않는다.

  네트워크 호출은 스트림 소비 시점에 일어날 수 있다(어댑터 구현 자유).
  """
  @callback stream_text(Model.t(), Context.t(), opts) ::
              {:ok, event_stream} | {:error, term}

  @doc "이 어댑터가 주어진 모델을 처리할 수 있는지 확인한다."
  @callback supports?(Model.t()) :: boolean
end
