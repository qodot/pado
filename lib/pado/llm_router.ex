defmodule Pado.LLMRouter do
  @moduledoc """
  LLM 프로바이더 API와 OAuth 플로우를 묶어 다루는 Elixir SDK.

  `@mariozechner/pi-ai`(TypeScript)와 `req_llm`(Elixir)에서 영감을 받았다.

  최상위 모듈 자체에는 공개 API가 없다. 라이브러리는 하위 시스템별로
  나뉘어 있다.

    * `Pado.LLMRouter.OAuth.Provider` — OAuth 기반 프로바이더의 behaviour.
    * `Pado.LLMRouter.OAuth.OpenAICodex` — ChatGPT Plus/Pro(Codex) 로그인.
    * `Pado.LLMRouter.OAuth.Credentials` — 크레덴셜 구조체와 JSON 헬퍼.
    * `Pado.LLMRouter.OAuth.CallbackServer` — 일회성 HTTP 리스너(선택 의존성).
    * `Mix.Tasks.Pado.LlmRouter.Login` — 레퍼런스 CLI(`mix llm_router.login`).

  스트리밍·completion API는 이후 마일스톤에서 추가한다.
  """
end
