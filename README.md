# Pado

> 서버사이드 LLM 에이전트를 OTP 위에서 짓기 위한 Elixir 생태계.

`Pado`(파도)는 LLM 프로바이더 클라이언트부터 에이전트 런타임·웹 UI까지, 서버에서
장기 실행되는 AI 에이전트를 만드는 데 필요한 계층을 쌓아 간다. 각 계층은 `Pado.*`
네임스페이스 아래 독립된 하위 시스템으로 공존한다.

> **상태: 초기 단계.** 현재는 `Pado.LLMRouter`(LLM 프로바이더 API 클라이언트)만
> 구현 중이다. OpenAI Codex(ChatGPT Plus/Pro 구독) OAuth 로그인, 크레덴셜 모델,
> `/codex/responses` 스트리밍 호출, SSE 파싱, 정규화 이벤트 매핑까지 1차 구현되어
> 있다. 에이전트 루프와 웹 UI는 아직 없다.

---

## 참고한 프로젝트

Pado의 설계는 두 프로젝트에서 **강력한 영향**을 받았다. 개념 계층 대부분을
그대로 빌려 왔고, 그 위에서 Elixir/OTP와 서버사이드 환경에 맞게 다시 빚었다.

### [Pi (`@mariozechner/pi-mono`)](https://github.com/badlogic/pi-mono)

Mario Zechner의 TypeScript 기반 터미널 코딩 에이전트.
특히 다음 패키지들의 설계를 정독하고 가져왔다:

- **`pi-ai`** — LLM 프로바이더 어댑터 레지스트리, OAuth 구독 로그인 플로우,
  스트리밍 이벤트 추상. `Pado.LLMRouter`의 거의 모든 추상이 여기서 왔다.
  OpenAI Codex OAuth 플로우(엔드포인트, 비표준 파라미터, JWT 클레임 구조)도
  pi-ai의 `utils/oauth/openai-codex.ts`를 사실상 포트한 것이다.
- **`pi-agent-core`** — 에이전트 루프(턴 반복, 도구 실행, steer/followUp
  메시지 큐잉, 세분화된 `AgentEvent` 스트림). 향후 `Pado.Agent`가 참조할 설계.

### [Jido (`agentjido/jido`, `jido_ai`, `jido_action`)](https://github.com/agentjido/jido)

Mike Hostetler의 Elixir 자율 에이전트 프레임워크.
OTP 위에서 상태 있는 에이전트를 **불변 `cmd/2` + Directive + Signal 라우팅 +
AgentServer**로 정렬한 모델을 참고한다. 특히:

- **`jido`(코어)** — 감독트리 통합, 파티션 멀티테넌시, 스케줄러, 플러그인.
  향후 `Pado.Agent`의 런타임 기반.
- **`jido_ai`** — ReAct 전략, Request/Run/Iteration 개념 계층, 체크포인트 재개.
- **`jido_action`** — 검증된 Action이 LLM 도구로도 쓰이는 이중 역할.

### 그 외

- **[`req_llm`](https://hex.pm/packages/req_llm)** — Elixir용 멀티 프로바이더
  LLM HTTP 클라이언트. 장기적으로 `Pado.LLMRouter`의 일부 프로바이더를
  `req_llm` 어댑터로 위임할 가능성을 열어 둔다.

> 위 프로젝트들은 각자의 철학·실행 모델이 다르고, 이 저장소에도 그 차이의 흔적이
> 그대로 녹아 있다. Pado는 두 설계의 복제가 아니라, **"Pi의 API 모양 + Jido의
> OTP 런타임"** 을 이식하려는 시도다.

---

## 왜 Pado인가

네 가지 전제에서 출발한다.

1. **실행 환경은 서버사이드다.** 터미널 CLI가 아니라 장기 실행되는 Elixir
   애플리케이션 안에서 에이전트가 돈다.
2. **멀티 에이전트·멀티테넌시가 자연스러워야 한다.** 세션별로 격리된 프로세스,
   감독트리, 파티션이 필요하면 Jido의 원시요소를 그대로 쓴다.
3. **사용자 상호작용은 주로 웹 UI**(Phoenix LiveView)다. 따라서 이벤트 스트림은
   PubSub/Channel과 자연스럽게 맞물려야 한다.
4. **LLM 프로바이더·OAuth 세부사항은 한 번 쓰고 잊고 싶다.** Pi의 pi-ai가 이미
   만들어 둔 것을 Elixir 관용구로 옮기면 된다.

이 조합은 Pi에도 Jido에도 그대로 존재하지 않는다. 둘의 공통 부분집합에 OTP 운영성
위에서 서버사이드 UX를 얹는 것이 Pado가 메우려는 빈칸이다.

---

## 생태계 구조

`Pado`는 생태계 진입점 모듈이고, 실제 기능은 하위 시스템에 들어간다.

| 하위 시스템 | 상태 | 대응하는 참고 구현 |
|---|---|---|
| `Pado.LLMRouter` | **구현 중** (OpenAI Codex OAuth + 스트리밍) | `pi-ai`, `req_llm` |
| `Pado.Agent` | 미착수 | `pi-agent-core`, `jido` + `jido_ai` |
| `Pado.Web` | 미착수 | (Pi의 `web-ui`, LiveView 통합) |

하위 시스템은 같은 저장소(`qodot/pado`)에서 관리되며, 필요해지면 별도 Hex
패키지로 분리할 수 있도록 네임스페이스부터 격리해 둔다.

---

## `Pado.LLMRouter` — 현재 구현된 것

| 모듈 | 역할 |
|---|---|
| `Pado.LLMRouter` | `stream/3` 공개 진입점 |
| `Pado.LLMRouter.Provider` | 프로바이더 호출 behaviour |
| `Pado.LLMRouter.Model` | 모델 메타데이터와 비용 계산 |
| `Pado.LLMRouter.Context` | 시스템 프롬프트, 메시지, 도구 목록 입력 묶음 |
| `Pado.LLMRouter.Message.*` | User/Assistant/ToolResult 메시지 구조체 |
| `Pado.LLMRouter.Tool` | LLM에 노출할 함수 도구 스키마 |
| `Pado.LLMRouter.Usage` | 토큰 사용량과 비용 정규화 |
| `Pado.LLMRouter.Event` | 스트리밍 이벤트 유니언 타입 |
| `Pado.LLMRouter.Catalog.OpenAICodex` | ChatGPT 계정에서 호출 가능한 Codex 모델 카탈로그 |
| `Pado.LLMRouter.Providers.OpenAICodex.Request` | `/codex/responses` 요청 URL·헤더·바디 조립 |
| `Pado.LLMRouter.Providers.OpenAICodex.SSE` | Server-Sent Events 청크 파서 |
| `Pado.LLMRouter.Providers.OpenAICodex.EventMapper` | Codex SSE 이벤트를 Pado 이벤트로 정규화 |
| `Pado.LLMRouter.Providers.OpenAICodex` | Finch 기반 실제 스트리밍 어댑터 |
| `Pado.LLMRouter.OAuth.Provider` | OAuth 기반 프로바이더 behaviour |
| `Pado.LLMRouter.OAuth.Credentials` | 크레덴셜 구조체 + JSON 직렬화/역직렬화 |
| `Pado.LLMRouter.OAuth.PKCE` | RFC 7636 기반 verifier/challenge/state |
| `Pado.LLMRouter.OAuth.OpenAICodex` | ChatGPT Plus/Pro (Codex) 로그인·갱신 |
| `Pado.LLMRouter.OAuth.Callback.Server` | 일회성 `127.0.0.1:1455` 리스너 (선택 의존성) |
| `Mix.Tasks.Pado.LlmRouter.Login` | 콜백을 stdin/stdout에 배선한 레퍼런스 CLI |

### 설계 메모

- **라이브러리는 어떤 영속 저장소도 소유하지 않는다.** `login/2`는
  `%Credentials{}`를 반환할 뿐이고, 저장·갱신·로테이션 관리는 호출자(서비스 앱)
  책임이다. Pi가 `pi-coding-agent`의 `AuthStorage`에 그 책임을 분리해 둔 것과
  같은 원칙.
- **콜백 서버는 라이브러리 안에 내장**되어 있다. OpenAI의 `redirect_uri`가
  `http://localhost:1455/auth/callback`으로 서버에 등록되어 있어 우회할 수 없는
  프로토콜 상수이기 때문이다. 다만 UI·저장·프롬프트는 전부 호출자가 주입하는
  콜백 맵으로 분리된다.
- **`:bandit`/`:plug`는 선택 의존성**이다. 이미 크레덴셜을 가진 서비스(예:
  Vault에서 로드)는 콜백 서버를 깔 필요가 없다.
- **`Pado.LLMRouter`는 도구를 실행하지 않는다.** 도구 목록을 모델에 알려주고,
  모델이 요청한 `tool_call`을 정규화된 Assistant 메시지로 돌려주는 데까지만
  책임진다. 실제 도구 실행과 다음 턴 반복은 향후 `Pado.Agent`의 책임이다.
- **스트리밍은 이벤트 Enumerable로 노출한다.** 상위 계층은 토큰 델타,
  tool_call 델타, 종료 이벤트를 그대로 소비한다.

### 사용 방법

#### 1. 크레덴셜 발급 (환경당 1회, 브라우저가 있는 머신)

```bash
$ mix pado.llm_router.login > ~/.config/pado/openai.json
```

브라우저가 열리고 `localhost:1455`로 콜백이 돌아오면 다음과 같은 JSON이 출력된다:

```json
{
  "provider": "openai_codex",
  "access": "eyJhbGci…",
  "refresh": "…",
  "expires_at": "2026-04-23T08:00:00.000000Z",
  "extra": { "account_id": "acct_…", "originator": "pi" }
}
```

#### 2. 앱에서 로드 + 자동 갱신 + 스트리밍 호출

```elixir
alias Pado.LLMRouter
alias Pado.LLMRouter.Catalog.OpenAICodex, as: OpenAICodexCatalog
alias Pado.LLMRouter.Context
alias Pado.LLMRouter.Message.User
alias Pado.LLMRouter.OAuth.{Credentials, OpenAICodex}

path = Path.expand("~/.config/pado/openai.json")

{:ok, creds} =
  path
  |> File.read!()
  |> Jason.decode!()
  |> Credentials.from_map()

creds =
  if Credentials.stale?(creds, 60) do
    {:ok, refreshed} = OpenAICodex.refresh(creds)
    File.write!(path, Jason.encode!(Credentials.to_map(refreshed), pretty: true))
    refreshed
  else
    creds
  end

model = OpenAICodexCatalog.default()
ctx = Context.new(messages: [User.new("안녕. 한 문장으로 자기소개해줘.")])

{:ok, stream} = LLMRouter.stream(model, ctx, creds, reasoning_effort: :low)

Enum.each(stream, fn
  {:text_delta, %{delta: delta}} -> IO.write(delta)
  {:tool_call_start, %{name: name}} -> IO.puts("\n도구 호출 요청: #{name}")
  {:done, %{usage: usage}} -> IO.puts("\n완료: #{inspect(usage)}")
  {:error, %{error_message: message}} -> IO.puts(:stderr, "오류: #{message}")
  _ -> :ok
end)
```

> 매 `refresh/1` 호출마다 서버가 새 `refresh_token`을 발급한다(로테이션).
> 반환된 크레덴셜을 반드시 저장해야 다음 갱신이 가능하다. 직접 HTTP 헤더를
> 조립해야 하는 특수한 경우에는 `OpenAICodex.api_key/1`로 bearer 토큰을 꺼낼 수 있다.

#### 3. `login/2`를 직접 호출 (Mix task 없이)

```elixir
callbacks = %{
  on_auth: fn %{url: url} -> IO.puts("이 URL을 여세요: #{url}") end,
  on_prompt: fn %{message: m} ->
    {:ok, IO.gets(m) |> String.trim()}
  end,
  on_progress: fn msg -> IO.puts(msg) end
}

{:ok, creds} = Pado.LLMRouter.OAuth.OpenAICodex.login(callbacks)
```

---

## 로드맵

구체적 약속이 아니라 방향성 스케치.

- **Pado.LLMRouter 안정화** — 단위/통합 테스트 확장, Codex HTTP 전송 계층 분리,
  timeout/transport 오류 처리 정교화, reasoning/thinking 이벤트 매핑.
- **프로바이더 확장** — Anthropic Messages API 직접 어댑터, 필요 시 `req_llm`
  위임 어댑터, 모델 카탈로그 갱신 자동화.
- **Pado.Agent** — `use Jido.Agent` 위에 Pi 스타일 에이전트 루프(턴 반복,
  도구 실행, steer/followUp 큐, 세분화된 이벤트 스트림)를 얇게 얹음.
  `jido_ai`의 ReAct 전략을 그대로 쓰기보다 루프 의사결정을 소유하는 쪽으로 기운다.
- **Pado.Web** — LiveView용 `Pado.Agent` 바인딩. 1:1 사용자 세션을 스트림 직접
  소비 방식으로 렌더.

---

## 설치

아직 Hex에 게시되지 않았다. path 또는 git 의존성으로 사용한다.

```elixir
def deps do
  [
    {:pado, github: "qodot/pado", branch: "main"}
  ]
end
```

또는 모노레포 안이라면:

```elixir
def deps do
  [
    {:pado, path: "../pado"}
  ]
end
```

---

## 프로젝트 지침

- 모든 문서·주석·커밋 메시지는 **한국어**로 작성한다.
- 커밋은 작은 단위로 쪼개고, Conventional Commits prefix(`feat:`, `fix:`,
  `refactor:`, `docs:`, …)를 쓰되 설명은 한국어로.
- 코드 식별자는 영어를 유지한다.

자세한 규칙은 `AGENTS.md` 참고.

---

## 출처와 감사

`Pado.LLMRouter.OAuth.OpenAICodex`의 동작(엔드포인트, 비표준 `authorize`
파라미터, JWT 클레임 구조, 콜백 UX)은 **pi-mono 저자들이 역공학해 공개한 경로**를
그대로 따른다. 같은 구조를 따르므로, 양쪽에서 만든 크레덴셜은
`Credentials.from_map/1`의 `expires_at` 변환을 거치면 상호 호환된다.

Pi와 Jido가 없었다면 Pado는 지금의 설계에 훨씬 오래 걸려 도달했을 것이다.
두 프로젝트 저자들에게 감사를 표한다.

---

## 라이선스

MIT. (추가 예정: `LICENSE` 파일)
