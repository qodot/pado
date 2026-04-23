# LLMRouter

Elixir SDK for routing requests to LLM provider APIs. Inspired by
[`@mariozechner/pi-ai`](https://github.com/badlogic/pi-mono/tree/main/packages/ai)
(TypeScript) and [`req_llm`](https://hex.pm/packages/req_llm).

> **Status:** early — OAuth login flow (OpenAI Codex subscription) and
> credential model only. Streaming/completion APIs to follow.

## What's here

| Module | Role |
|---|---|
| `LLMRouter.OAuth.Provider` | Behaviour for OAuth-based providers |
| `LLMRouter.OAuth.Credentials` | Credential struct + JSON (de)serialisation |
| `LLMRouter.OAuth.PKCE` | RFC 7636 verifier/challenge/state |
| `LLMRouter.OAuth.OpenAICodex` | ChatGPT Plus/Pro (Codex) login/refresh |
| `LLMRouter.OAuth.CallbackServer` | One-shot `127.0.0.1:1455` listener |
| `Mix.Tasks.LlmRouter.Login` | Reference CLI that wires callbacks to stdin/stdout |

## Design at a glance

OAuth flows have two inescapable constraints:

1. **`redirect_uri` is server-registered.** OpenAI's Codex simplified flow
   requires `http://localhost:1455/auth/callback`, which means the login
   must happen on the machine that has a browser.
2. **Tokens must be stored somewhere.** That "somewhere" varies — a
   dotfile, Vault, a secret manager, a DB.

LLMRouter therefore splits responsibilities cleanly:

- The library **runs the OAuth protocol** (`OpenAICodex.login/2`) and
  owns the short-lived HTTP callback listener. All user interaction
  (browser, prompts, progress) is injected via a `callbacks` map.
- The library **does not store** credentials. `login/2` returns a
  `%Credentials{}` struct; the caller decides what to do with it.
- The Mix task is a minimal reference CLI that prints the credentials as
  JSON to stdout. Use it once per environment, capture the output.

## Usage

### 1. Mint credentials (once per user/environment)

```bash
$ mix llm_router.login > ~/.config/llm-router/openai.json
```

That opens a browser, waits for the callback on `localhost:1455`, exchanges
the code, and prints a JSON document like:

```json
{
  "provider": "openai_codex",
  "access": "eyJhbGci…",
  "refresh": "…",
  "expires_at": "2026-04-23T08:00:00.000000Z",
  "extra": { "account_id": "acct_…", "originator": "pi" }
}
```

### 2. Load + refresh in your app

```elixir
creds =
  "~/.config/llm-router/openai.json"
  |> Path.expand()
  |> File.read!()
  |> Jason.decode!()
  |> LLMRouter.OAuth.Credentials.from_map()
  |> then(fn {:ok, c} -> c end)

creds =
  if LLMRouter.OAuth.Credentials.stale?(creds, 60) do
    {:ok, refreshed} = LLMRouter.OAuth.OpenAICodex.refresh(creds)
    File.write!(path, Jason.encode!(LLMRouter.OAuth.Credentials.to_map(refreshed)))
    refreshed
  else
    creds
  end

access_token = LLMRouter.OAuth.OpenAICodex.api_key(creds)
```

> **Note:** every refresh returns a *new* `refresh_token` (rotation).
> Always persist the returned credentials.

### 3. Calling `login/2` yourself (without the Mix task)

```elixir
callbacks = %{
  on_auth: fn %{url: url} -> IO.puts("open: #{url}") end,
  on_prompt: fn %{message: m} ->
    {:ok, IO.gets(m) |> String.trim()}
  end,
  on_progress: fn msg -> IO.puts(msg) end
}

{:ok, creds} = LLMRouter.OAuth.OpenAICodex.login(callbacks)
```

## Optional dependencies

`:bandit` and `:plug` are declared `optional: true`. They are only
required when you actually run a login flow. Services that already hold
credentials (read from Vault at boot, refreshed in-process) do not need
them.

## Installation

Not on Hex yet. Use as a path dependency:

```elixir
def deps do
  [
    {:llm_router, path: "../llm-router"}
  ]
end
```

## Provenance

The OpenAI Codex OAuth flow (endpoints, non-standard query parameters,
JWT claim shape, callback UX) was reverse-engineered and documented by
pi-mono's authors. This library follows the same shape so that
credentials produced by either tool are interchangeable (given the
`expires_at` format helper in `Credentials.from_map/1`).
