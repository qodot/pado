# LLMRouter

여러 LLM 프로바이더 API와 OAuth 플로우를 묶어 다루는 Elixir SDK.
[`@mariozechner/pi-ai`](https://github.com/badlogic/pi-mono/tree/main/packages/ai)(TypeScript)와
[`req_llm`](https://hex.pm/packages/req_llm)(Elixir)에서 영감을 받았다.

> **상태:** 초기 단계 — OpenAI Codex(ChatGPT 구독) OAuth 로그인 플로우와
> 크레덴셜 모델만 구현되어 있다. 스트리밍/completion API는 이후 마일스톤.

## 지금 들어 있는 것

| 모듈 | 역할 |
|---|---|
| `LLMRouter.OAuth.Provider` | OAuth 프로바이더 behaviour |
| `LLMRouter.OAuth.Credentials` | 크레덴셜 구조체와 JSON 직렬화 |
| `LLMRouter.OAuth.PKCE` | RFC 7636 기반 verifier/challenge/state |
| `LLMRouter.OAuth.OpenAICodex` | ChatGPT Plus/Pro(Codex) 로그인 · 갱신 |
| `LLMRouter.OAuth.CallbackServer` | 일회성 `127.0.0.1:1455` 리스너 |
| `Mix.Tasks.LlmRouter.Login` | 콜백을 stdin/stdout에 배선한 레퍼런스 CLI |

## 설계 요약

OAuth 플로우에는 피할 수 없는 제약이 둘 있다.

1. **`redirect_uri`는 서버에 등록되어 있다.** OpenAI Codex simplified
   플로우는 `http://localhost:1455/auth/callback`을 요구한다. 즉
   로그인은 브라우저가 있는 머신에서 실행되어야 한다.
2. **토큰은 어딘가에 저장되어야 한다.** 그 "어딘가"는 dotfile, Vault,
   시크릿 매니저, DB 등 환경마다 다르다.

LLMRouter는 이 두 제약을 존중하도록 책임을 분리한다.

- 라이브러리는 **OAuth 프로토콜을 실행**(`OpenAICodex.login/2`)하고,
  수명이 짧은 HTTP 콜백 리스너를 내부에서 띄운다. 사용자 상호작용
  (브라우저 열기·프롬프트·진행 알림)은 모두 `callbacks` 맵으로 주입한다.
- 라이브러리는 **크레덴셜을 저장하지 않는다.** `login/2`는
  `%Credentials{}` 구조체를 돌려줄 뿐이며, 이후 저장과 갱신은 호출자
  결정이다.
- Mix task는 그 최소한을 구현한 레퍼런스 CLI다. 크레덴셜을 JSON으로
  stdout에 출력한다. 환경마다 한 번 돌려 출력 값을 원하는 저장소에
  둔다.

## 사용 방법

### 1. 크레덴셜 발급(환경 당 1회)

```bash
$ mix llm_router.login > ~/.config/llm-router/openai.json
```

브라우저가 열리고 `localhost:1455`로 콜백이 돌아오면, 코드를 교환한 뒤
다음과 같은 JSON을 출력한다.

```json
{
  "provider": "openai_codex",
  "access": "eyJhbGci…",
  "refresh": "…",
  "expires_at": "2026-04-23T08:00:00.000000Z",
  "extra": { "account_id": "acct_…", "originator": "pi" }
}
```

### 2. 앱에서 로드·갱신

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

> **주의:** 매 갱신마다 서버가 새 `refresh_token`을 발급한다(로테이션).
> 반환된 크레덴셜을 반드시 다시 저장해야 다음 갱신이 가능하다.

### 3. `login/2`를 직접 호출하기(Mix task 없이)

```elixir
callbacks = %{
  on_auth: fn %{url: url} -> IO.puts("브라우저에서 이 URL을 여세요: #{url}") end,
  on_prompt: fn %{message: m} ->
    {:ok, IO.gets(m) |> String.trim()}
  end,
  on_progress: fn msg -> IO.puts(msg) end
}

{:ok, creds} = LLMRouter.OAuth.OpenAICodex.login(callbacks)
```

## 선택 의존성

`:bandit`과 `:plug`는 `optional: true`로 선언되어 있다. 로그인 플로우를
실제로 실행할 때만 필요하다. 이미 크레덴셜을 가지고 있는 서비스(부팅 시
Vault에서 읽고 인프로세스에서 갱신)는 설치하지 않아도 된다.

## 설치

아직 Hex에 올라가 있지 않다. path 의존성으로 사용한다.

```elixir
def deps do
  [
    {:llm_router, path: "../llm-router"}
  ]
end
```

## 출처

OpenAI Codex OAuth 플로우(엔드포인트, 비표준 쿼리 파라미터, JWT 클레임
구조, 콜백 UX)는 pi-mono 저자들이 역공학해 문서화한 경로다. 이
라이브러리는 그 구조를 그대로 따라가므로, 양쪽에서 만든 크레덴셜은
`Credentials.from_map/1`의 `expires_at` 변환 헬퍼를 거치면 상호
호환된다.
