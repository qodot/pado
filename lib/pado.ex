defmodule Pado do
  @moduledoc """
  Pado — LLM 기반 자율 에이전트를 위한 Elixir 생태계의 진입점 모듈.

  이 모듈 자체에는 공개 API가 없고, 생태계의 하위 시스템이 `Pado.*` 네임스페이스
  아래에 모인다.

    * `Pado.LLMRouter` — LLM 프로바이더 API 클라이언트 (`@mariozechner/pi-ai`,
      `req_llm` 대응). 현재 이 패키지의 유일한 하위 시스템.

  향후 추가될 계층(안):

    * `Pado.Agent` — LLM 에이전트 루프(ReAct·도구 실행·메시지 큐잉).
    * `Pado.Web` — Phoenix LiveView 통합 컴포넌트.
  """
end
