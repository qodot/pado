defmodule LLMRouter do
  @moduledoc """
  LLMRouter — a unified Elixir SDK for LLM provider APIs and OAuth flows.

  Inspired by `@mariozechner/pi-ai` (TypeScript) and `req_llm` (Elixir).

  This top-level module currently exposes no public API — the library is
  organized by subsystem:

    * `LLMRouter.OAuth.Provider` — behaviour for OAuth-based providers.
    * `LLMRouter.OAuth.OpenAICodex` — ChatGPT Plus/Pro (Codex) login.
    * `LLMRouter.OAuth.Credentials` — credential struct + JSON helpers.
    * `LLMRouter.OAuth.CallbackServer` — one-shot HTTP listener (optional).
    * `Mix.Tasks.LLMRouter.Login` — reference CLI (`mix llm_router.login`).

  Streaming/completion APIs will be added in subsequent milestones.
  """
end
