# LLMRouter 기반 에이전트 루프 설계

> 생성일: 2026-04-26 23:07
> 갱신일: 2026-04-26 23:07
> 상태: 계획됨 — Pi식 직접 루프 우선, Jido식 Signal/Directive는 후순위

## 개요

`Pado.LLMRouter`는 provider 호출, SSE 파싱, 정규화 이벤트, assistant 메시지 완성까지만 맡는다. 새 `Pado.Agent`의 1차 목표는 그 위에 **Pi식 직접 Run/Turn 루프**를 얹는 것이다.

Jido core의 `Signal → Strategy/Action → Directive → DirectiveExec` 구조는 서버형 장기 실행 agent runtime에는 유용하지만, 1차 LLM agent loop에는 과하다. 따라서 처음에는 signal/directive를 만들지 않고, `Pado.Agent.Loop`가 직접 `LLMRouter.stream/5`를 호출하고 tool을 실행한다. 이후 서버/멀티에이전트/스케줄/외부 이벤트 요구가 생기면 `Pado.Agent.Server` 또는 별도 adapter에서 Jido식 runtime 경계를 도입한다.

## 대화 후 확정한 판단

### 1. Pado의 기본 용어

```text
Session
└── Request        # 사용자가 "X 해"라고 보낸 외부 요청 단위. 서버 계층에서 의미가 커진다.
    └── Run        # 그 요청을 처리하는 실제 에이전트 실행 구간.
        ├── Turn 1 # LLM 응답 1회 + 그 응답의 tool_call 실행 묶음.
        ├── Turn 2
        └── RunEnd # 최종 assistant 응답 또는 실패/중단.
```

- **Run**: “사용자 요청 → 여러 LLM/tool 턴 → 최종 응답” 전체 실행 단위.
- **Turn**: LLM 호출 1회와 그 assistant 메시지가 요청한 tool 실행 묶음.
- **Request**: 서버 API/동시성/await가 필요해질 때의 외부 요청 단위. 1차 직접 루프에서는 `request_id`가 optional이어도 된다.
- **Event**: UI/호출자가 구독하는 관찰 스트림. 1차 이벤트명은 `agent_start/end`보다 `run_start/end`를 쓴다. OTP/Jido 맥락에서 `agent_start`는 프로세스 시작으로 오해될 수 있다.

### 2. Pi와 Jido의 차이

Pi와 Jido가 필요로 하는 UX는 비슷할 수 있다. 예를 들어 실행 중 끼어들기, follow-up, abort, tool 승인, child/sub-agent 같은 요구는 Pi에도 Jido에도 존재할 수 있다. 차이는 UX가 아니라 **내부 추상**이다.

| UX/기능 | Pi식 표현 | Jido식 표현 |
|---|---|---|
| 사용자 요청 | `session.prompt/agent.prompt` | `Signal` + request API |
| 실행 중 끼어들기 | `steer()` queue | `user.steer` 같은 signal + state transition |
| 후속 요청 | `followUp()` queue | 새 signal/request 또는 pending input |
| 중단 | `abort()` / AbortController | cancel signal + directive/runtime 처리 |
| tool 실행 | loop 내부 `tool.execute` | `ToolExec` directive 또는 runtime worker |
| child/sub-agent | extension/tool이 직접 구현 | `SpawnAgent` directive + parent/child tracking |
| 외부 이벤트/스케줄 | extension/SDK가 직접 호출 | Signal/Schedule/Cron primitive |

Pado 1차는 Pi처럼 **직접 메서드/큐/hook/event stream**으로 푼다. Jido식 signal/directive 일반화는 나중에 필요가 생기면 추가한다.

### 3. Jido core / Jido.AI / provider 책임 경계

Jido 계층은 다음처럼 분리된다.

```text
사용자 / 앱 코드
  │ MyAgent.ask(pid, "X 해")
  ▼
Jido.AI
  - Request 생성
  - request_id/run_id/iteration/call_id 부여
  - ReAct Strategy/Runner
  - LLM message/tool schema 구성
  - runtime event를 request/run으로 rollup
  │
  ▼
Jido core
  - AgentServer 프로세스
  - Signal routing
  - Strategy/Action cmd 호출
  - DirectiveExec protocol dispatch
  - SpawnAgent/Emit/Schedule/Stop 같은 runtime 효과 실행
  - agent state/children/await/supervision 관리
  │
  ▼
ReqLLM
  - provider 공통 client
  - `stream_text` / `generate_text`
  │
  ▼
LLM Provider
  - OpenAI / Anthropic / Gemini 등 실제 API
```

중요한 결론:

- Jido core는 LLM provider를 모른다.
- Jido core는 “directive를 실행하라”는 runtime machinery를 제공한다.
- LLM 호출 의미와 구현은 `jido_ai`의 `LLMStream`/`LLMGenerate`/`ReAct.Runner`와 `req_llm`이 소유한다.
- `Signal → Directive`가 직접 매핑되는 것이 아니다.
  - SignalRouter가 signal type을 Action/Strategy command로 라우팅한다.
  - Strategy/Action이 현재 state와 payload를 보고 어떤 directive를 낼지 결정한다.
  - AgentServer가 directive struct 타입에 맞는 `DirectiveExec` 구현을 호출한다.
- child를 spawn할지도 core가 결정하지 않는다. Strategy/Action이 state를 보고 `SpawnAgent` directive를 반환하면 core가 실행·추적할 뿐이다.

Pado 대응 관계:

```text
Jido core         ≈ Pado.Agent.Server / OTP runtime wrapper (2차 이후)
Jido.AI           ≈ Pado.Agent.Loop / Run-Turn loop
ReqLLM + provider ≈ Pado.LLMRouter
```

따라서 Pado 1차에서 만들어야 하는 것은 Jido core 같은 범용 runtime이 아니라 **Jido.AI/Pi agent loop에 해당하는 직접 Run/Turn 루프**다.

## 참고 사례에서 가져올 것

### Pi에서 가져올 것

- 직접 loop 구조: `prompt/run → turn → LLM stream → tool execution → next turn → run end`.
- 한 Turn의 정의: “LLM assistant 응답 1회 + 해당 응답의 tool_call 실행 묶음”.
- tool_call이 있으면 assistant 메시지와 tool_result 메시지를 컨텍스트에 추가하고 다음 Turn을 돈다.
- steering 메시지는 현재 assistant 턴의 도구 실행이 끝난 뒤 다음 LLM 호출 전에 주입한다.
- follow-up 메시지는 더 이상 tool/steering이 없을 때만 새 Turn으로 주입한다.
- 세션 저장, compaction, UI, 권한 확인은 core loop 밖에 둔다.
- 이벤트는 UI가 그대로 소비할 수 있게 세분화한다.

### Jido/Jido.AI에서 가져올 것

- `request_id`, `run_id`, `turn_index`/`iteration`, `llm_call_id`, `tool_call_id` 같은 correlation id를 처음부터 이벤트에 심는다.
- 실행 중 누적 컨텍스트와 커밋된 컨텍스트를 구분한다. 1차에서는 단순화해도 되지만, server 계층에서는 `run_context` 개념을 고려한다.
- tool 실행 결과는 성공/실패 의미를 명확히 담아 다음 LLM 턴에 투영한다.
- 장기 실행 server는 request 상태, active request, queue, subscriber, abort를 소유한다.
- 크레덴셜 저장, 세션 저장, PubSub/LiveView 연결은 호출자 앱 또는 server wrapper가 소유한다.

### 지금 가져오지 않을 것

- Jido core의 범용 Signal/Directive 시스템.
- `SpawnAgent` 기반 worker 계층.
- `use Jido.Agent` 의존성.
- 외부 webhook/scheduler/child agent까지 포괄하는 범용 runtime protocol.

## 핵심 원칙

**이 세 가지는 플랜 전체를 관통하는 최우선 원칙이다. 모든 설계 결정에서 이 원칙을 먼저 적용한다.**

### 1. 함수형 프로그래밍

- **순수 함수 우선**: 상태 갱신, tool_call 추출, 메시지 추가는 순수 함수로 둔다.
- **불변성**: `RunState`와 `Context`는 새 값을 반환한다.
- **부수효과 격리**: LLM 호출, tool 실행, 이벤트 송신, 프로세스 관리는 루프 셸에 둔다.
- **선언적 표현**: 루프의 각 단계는 `call_model → execute_tools → inject_queued_messages`처럼 데이터 흐름으로 표현한다.

### 2. 조합 가능한 인터페이스로서의 함수 시그니처

- **단일 책임**: LLM 스트림 소비, tool 실행, 큐 드레인, 이벤트 변환을 분리한다.
- **입출력 일관성**: `Assistant.t()`에서 tool_call 목록을 추출하고, tool 실행 결과는 곧바로 `ToolResult.t()`로 반환한다.
- **작은 함수, 넓은 조합**: `Loop.stream/1`은 작은 내부 함수들을 순서대로 조합하는 orchestrator로 둔다.
- **의존성 주입**: 모델, 크레덴셜 resolver, tool registry, 큐 drain 함수, LLM 옵션을 모두 `Run` 입력으로 받는다.

### 3. TDD (Red-Green-Refactor)

- **테스트가 설계를 이끈다**: 실제 LLM 호출 없이 fake router와 fake tool로 루프 계약을 먼저 고정한다.
- **Red → Green → Refactor**: 순수 함수부터 실패 테스트를 만들고 최소 구현 후 다듬는다.
- **리프 노드부터**: tool_call 추출, tool 결과 포맷, 큐 드레인 같은 순수 함수부터 시작한다.
- **경계 케이스 우선**: tool 없음, 알 수 없는 tool, tool 실패, max_iterations, LLM error, abort를 테스트에 포함한다.

## 책임 분리

| 계층 | 1차 책임 | 포함하지 않을 것 |
|---|---|---|
| `Pado.LLMRouter` | provider 호출, 스트림 이벤트 정규화, assistant 메시지 완성 | 도구 실행, Turn 반복, Run 상태 |
| `Pado.Agent.Loop` | Pi식 Run/Turn 루프, 이벤트 방출, tool 실행 조합 | 세션 저장, PubSub, OTP request registry |
| `Pado.Agent.Tool*` | 실행 가능한 도구 정의, 결과를 `ToolResult`로 변환 | provider 포맷, UI 승인 흐름 |
| `Pado.Agent.Server` (2차) | request lifecycle, queue, subscriber, abort, OTP process | provider 세부사항, Jido 의존성 강제 |
| 호출자 앱 | 크레덴셜 저장/갱신, 세션 저장, LiveView/PubSub 연결 | provider별 HTTP 세부사항 |

## 함수 설계

### 시그니처 목록

```elixir
# 📁 lib/pado/agent/run.ex
[NEW] def new(opts) :: {:ok, t()} | {:error, term()}                         # ✅ 순수
# 모델, 컨텍스트, 도구, 크레덴셜 resolver, 루프 옵션을 검증해 실행 설정을 만든다.

[NEW] def router_tools(%t{}) :: [Pado.LLMRouter.Tool.t()]                    # ✅ 순수
# 실행 가능한 agent tool에서 LLMRouter에 노출할 tool 스키마만 추출한다.

# 📁 lib/pado/agent/run_state.ex
[NEW] def init(Pado.Agent.Run.t()) :: t()                                     # ✅ 순수
# 초기 컨텍스트, turn_index, usage, status를 가진 루프 상태를 만든다.

[NEW] def append_messages(t(), [Message.t()]) :: t()                         # ✅ 순수
# user/assistant/tool_result 메시지를 컨텍스트에 순서대로 추가한다.

[NEW] def append_assistant(t(), Assistant.t()) :: t()                         # ✅ 순수
# assistant 메시지를 컨텍스트에 추가하고 마지막 assistant를 갱신한다.

[NEW] def append_tool_results(t(), [ToolResult.t()]) :: t()                   # ✅ 순수
# tool result 메시지들을 컨텍스트에 순서대로 추가한다.

[NEW] def next_turn(t()) :: t()                                               # ✅ 순수
# 다음 LLM 턴을 위해 turn_index를 증가시킨다.

# 📁 lib/pado/agent/tool.ex
[NEW] def new(Pado.LLMRouter.Tool.t(), execute_fun, opts \\ []) :: t()        # ✅ 순수
# LLM 노출 스키마와 실제 실행 함수를 묶은 도구를 만든다.

[NEW] def router_tool(t()) :: Pado.LLMRouter.Tool.t()                         # ✅ 순수
# LLMRouter.Context.tools에 넣을 tool 정의를 반환한다.

# 📁 lib/pado/agent/tool_registry.ex
[NEW] def new([Pado.Agent.Tool.t()]) :: {:ok, t()} | {:error, term()}          # ✅ 순수
# tool name 기준 registry를 만든다. 중복 이름은 오류로 반환한다.

[NEW] def fetch(t(), String.t()) :: {:ok, Pado.Agent.Tool.t()} | :error        # ✅ 순수
# tool_call 이름으로 실행 도구를 찾는다.

[NEW] def router_tools(t()) :: [Pado.LLMRouter.Tool.t()]                      # ✅ 순수
# registry의 모든 도구를 LLMRouter tool 목록으로 변환한다.

# 📁 lib/pado/agent/tool_calls.ex
[NEW] def extract(Assistant.t()) :: [map()]                                   # ✅ 순수
# assistant content에서 `{:tool_call, %{id, name, args}}` 블록을 순서대로 추출한다.

# 📁 lib/pado/agent/tool_executor.ex
[NEW] def execute_many([map()], ToolRegistry.t(), map(), keyword()) :: [ToolResult.t()]  # ⚡ 부수효과
# tool_call 목록을 실행하고 LLMRouter ToolResult 메시지 목록으로 변환한다.

[NEW] def execute_one(map(), ToolRegistry.t(), map(), keyword()) :: ToolResult.t()       # ⚡ 부수효과
# 단일 tool_call을 실행한다. unknown/exception/timeout은 error ToolResult로 변환한다.

[NEW] def format_result(map(), term()) :: ToolResult.t()                      # ✅ 순수
# tool 실행 반환값을 success/error ToolResult로 정규화한다.

# 📁 lib/pado/agent/assistant_stream.ex
[NEW] def consume(Enumerable.t(), emit_fun) :: {:ok, Assistant.t()} | {:error, Assistant.t()}  # ⚡ 부수효과
# LLMRouter 이벤트를 Agent message 이벤트로 중계하고 최종 assistant 메시지를 반환한다.

# 📁 lib/pado/agent/loop.ex
[NEW] def stream(Pado.Agent.Run.t()) :: Enumerable.t()                        # ⚡ 부수효과
# 별도 worker task에서 루프를 실행하고 이벤트 Enumerable을 반환한다.

[NEW] def drive(Pado.Agent.Run.t(), emit_fun) :: {:ok, Pado.Agent.Result.t()} | {:error, term()}  # ⚡ 부수효과
# 테스트와 server 래퍼에서 쓸 실제 루프 실행 함수다.

[NEW] def call_model(Pado.Agent.Run.t(), RunState.t(), emit_fun) :: {:ok, RunState.t()} | {:error, RunState.t()}  # ⚡ 부수효과
# 크레덴셜을 얻고 LLMRouter.stream을 호출한 뒤 assistant를 상태에 반영한다.

[NEW] def next_step(Pado.Agent.Run.t(), RunState.t(), [map()]) :: :tools | :steer | :follow_up | :done | {:error, term()}  # ✅ 순수
# tool_call, 큐, max_turns 기준으로 다음 루프 동작을 결정한다.

# 📁 lib/pado/agent/event.ex
[NEW] def terminal?(event()) :: boolean()                                     # ✅ 순수
# agent stream의 종료 이벤트 여부를 판별한다.

# 📁 lib/pado/agent/server.ex (2차)
[NEW] def start_link(opts) :: GenServer.on_start()                            # ⚡ 부수효과
# 장기 실행 에이전트 세션 프로세스를 시작한다.

[NEW] def prompt(server, content, opts \\ []) :: {:ok, request()} | {:error, term()}  # ⚡ 부수효과
# 새 요청을 등록하고 루프 worker를 시작한다.

[NEW] def steer(server, content, opts \\ []) :: :ok | {:error, term()}         # ⚡ 부수효과
# 활성 루프의 steering 큐에 사용자 메시지를 넣는다.

[NEW] def follow_up(server, content, opts \\ []) :: :ok | {:error, term()}     # ⚡ 부수효과
# 루프 종료 후 실행할 follow-up 큐에 메시지를 넣는다.

[NEW] def subscribe(server, subscriber) :: :ok                                # ⚡ 부수효과
# 루프 이벤트를 받을 프로세스를 등록한다.

[NEW] def abort(server, request_id \\ nil) :: :ok                              # ⚡ 부수효과
# 활성 루프를 중단한다.
```

### 핵심 데이터 모양

```elixir
defmodule Pado.Agent.Run do
  defstruct [
    :model,
    :credential_fun,
    :session_id,
    :context,
    :tool_registry,
    request_id: nil,
    run_id: nil,
    llm_opts: [],
    max_turns: 10,
    tool_concurrency: 4,
    tool_timeout_ms: 30_000,
    get_steering_messages: fn -> [] end,
    get_follow_up_messages: fn -> [] end,
    router: Pado.LLMRouter
  ]
end

defmodule Pado.Agent.Tool do
  defstruct [
    :definition,
    :execute,
    timeout_ms: nil,
    metadata: %{}
  ]
end
```

`credential_fun`은 저장소를 소유하지 않는 원칙을 지키기 위한 seam이다. 단순 사용자는 `fn -> {:ok, credentials} end`를 넣고, 서비스 앱은 이 함수 안에서 stale 체크와 refresh, 저장소 갱신을 수행한다.

### 이벤트 모양

```elixir
@type event ::
        {:run_start, %{run_id: String.t(), request_id: String.t() | nil}}
        | {:run_end, %{run_id: String.t(), request_id: String.t() | nil, result: term(), messages: [Message.t()], usage: Usage.t() | nil}}
        | {:turn_start, %{run_id: String.t(), turn_index: pos_integer()}}
        | {:turn_end, %{run_id: String.t(), turn_index: pos_integer(), message: Assistant.t(), tool_results: [ToolResult.t()]}}
        | {:message_start, %{run_id: String.t(), message: Message.t()}}
        | {:message_update, %{run_id: String.t(), llm_call_id: String.t() | nil, llm_event: Pado.LLMRouter.Event.t()}}
        | {:message_end, %{run_id: String.t(), message: Message.t()}}
        | {:tool_execution_start, %{run_id: String.t(), turn_index: pos_integer(), tool_call_id: String.t(), tool_name: String.t(), args: map()}}
        | {:tool_execution_end, %{run_id: String.t(), turn_index: pos_integer(), tool_call_id: String.t(), tool_name: String.t(), result: ToolResult.t(), is_error: boolean()}}
        | {:queue_update, %{run_id: String.t(), steering: [Message.t()], follow_up: [Message.t()]}}
        | {:error, %{run_id: String.t(), reason: term(), message: Message.Assistant.t() | nil}}
```

Pi 호환 이름이 필요하면 adapter에서 `run_start → agent_start`, `run_end → agent_end`로 변환한다. core 이벤트는 Pado 용어인 `run_*`을 우선한다.

### 호출 트리

```text
Pado.Agent.Loop.stream(run) -> Enumerable.t()                         📁 lib/pado/agent/loop.ex ⚡
└── start_worker(run, owner) -> pid                                    📁 lib/pado/agent/loop.ex ⚡
    └── drive(run, emit) -> Result.t()                                 📁 lib/pado/agent/loop.ex ⚡
        ├── RunState.init(run) -> RunState.t()                         📁 lib/pado/agent/run_state.ex ✅
        ├── emit({:run_start, ...})                                    📁 lib/pado/agent/loop.ex ⚡
        ├── loop_turns(run, state, emit) -> Result.t()                 📁 lib/pado/agent/loop.ex ⚡
        │   ├── emit({:turn_start, ...})                               📁 lib/pado/agent/loop.ex ⚡
        │   ├── call_model(run, state, emit) -> RunState.t()           📁 lib/pado/agent/loop.ex ⚡
        │   │   ├── run.credential_fun.() -> Credentials.t()           📁 호출자 주입 ⚡
        │   │   ├── Run.router_tools(run) -> [Tool.t()]                📁 lib/pado/agent/run.ex ✅
        │   │   ├── Context.put_tools(ctx, tools) -> Context.t()       📁 lib/pado/llm_router/context.ex ✅ [MOD 없음]
        │   │   ├── run.router.stream(model, ctx, creds, session_id, opts) -> Enumerable.t() 📁 lib/pado/llm_router.ex ⚡ [기존]
        │   │   └── AssistantStream.consume(stream, emit) -> Assistant.t() 📁 lib/pado/agent/assistant_stream.ex ⚡
        │   ├── ToolCalls.extract(assistant) -> [tool_call]            📁 lib/pado/agent/tool_calls.ex ✅
        │   ├── ToolExecutor.execute_many(calls, registry, ctx, opts) -> [ToolResult.t()] 📁 lib/pado/agent/tool_executor.ex ⚡
        │   │   ├── ToolRegistry.fetch(registry, name) -> Tool.t()     📁 lib/pado/agent/tool_registry.ex ✅
        │   │   ├── execute_tool_fun.(call, tool_context) -> result    📁 사용자 도구 ⚡
        │   │   └── format_result(call, result) -> ToolResult.t()      📁 lib/pado/agent/tool_executor.ex ✅
        │   ├── RunState.append_tool_results(state, results) -> state  📁 lib/pado/agent/run_state.ex ✅
        │   ├── run.get_steering_messages.() -> [User.t()]             📁 server/호출자 주입 ⚡
        │   ├── run.get_follow_up_messages.() -> [User.t()]            📁 server/호출자 주입 ⚡
        │   └── next_step(run, state, tool_calls) -> decision          📁 lib/pado/agent/loop.ex ✅
        └── emit({:run_end, ...})                                      📁 lib/pado/agent/loop.ex ⚡
```

## 루프 의사코드

```elixir
def drive(run, emit) do
  state = RunState.init(run)
  emit.({:run_start, %{run_id: state.run_id, request_id: run.request_id}})

  result = loop(run, state, emit)

  emit.({:run_end, Result.to_payload(result)})
  result
end

defp loop(run, state, emit) do
  if state.turn_index > run.max_turns do
    Result.max_turns(state)
  else
    emit.({:turn_start, %{run_id: state.run_id, turn_index: state.turn_index}})

    with {:ok, state} <- call_model(run, state, emit) do
      tool_calls = ToolCalls.extract(state.last_assistant)

      cond do
        tool_calls != [] ->
          tool_results = ToolExecutor.execute_many(tool_calls, run.tool_registry, tool_context(state), run_opts(run))
          state = RunState.append_tool_results(state, tool_results)
          emit.({:turn_end, %{run_id: state.run_id, turn_index: state.turn_index, message: state.last_assistant, tool_results: tool_results}})

          steering = run.get_steering_messages.()
          state = RunState.append_messages(state, steering)
          loop(run, RunState.next_turn(state), emit)

        steering = run.get_steering_messages.(); steering != [] ->
          state = RunState.append_messages(state, steering)
          emit.({:turn_end, %{run_id: state.run_id, turn_index: state.turn_index, message: state.last_assistant, tool_results: []}})
          loop(run, RunState.next_turn(state), emit)

        follow_up = run.get_follow_up_messages.(); follow_up != [] ->
          state = RunState.append_messages(state, follow_up)
          emit.({:turn_end, %{run_id: state.run_id, turn_index: state.turn_index, message: state.last_assistant, tool_results: []}})
          loop(run, RunState.next_turn(state), emit)

        true ->
          emit.({:turn_end, %{run_id: state.run_id, turn_index: state.turn_index, message: state.last_assistant, tool_results: []}})
          Result.done(state)
      end
    end
  end
end
```

실제 구현에서는 `get_steering_messages`와 `get_follow_up_messages`를 중복 호출하지 않도록 helper로 분리한다.

## 2차 OTP 래퍼 설계

1차 `Loop.stream/1`은 Jido식 runtime을 소유하지 않는다. 2차 `Pado.Agent.Server`는 단순 GenServer wrapper로 시작한다.

```text
Pado.Agent.Server GenServer
├── state.context
├── state.active_request_id
├── state.requests[request_id]
├── state.steering_queue
├── state.follow_up_queue
├── state.subscribers
└── state.worker
    └── Task: Pado.Agent.Loop.drive(run, emit_to_server)
```

- `prompt/3`는 idle일 때 request를 만들고 worker를 시작한다.
- busy 정책은 기본 `:reject`로 둔다. 병렬 요청은 실제 사용처가 생긴 뒤 추가한다.
- `steer/3`는 active request가 있을 때만 큐에 넣는다.
- `follow_up/3`는 active run이 있으면 follow-up 큐에 넣고, idle이면 호출자가 새 prompt를 보내게 한다.
- worker 이벤트는 server가 구독자에게 중계하고 request 상태를 갱신한다.
- 이 단계에서도 Jido 의존성을 추가하지 않는다.

Jido식 Signal/Directive는 3차 이후 옵션이다. 그때도 기존 `Pado.Agent.Loop`를 유지하고, signal/directive adapter가 loop를 감싸도록 한다.

## 범위 결정

### 1차에 포함

- LLMRouter 기반 multi-turn tool loop.
- `run_start/run_end`, `turn_start/turn_end`, message/tool 이벤트 스트림.
- 실행 가능한 Tool wrapper와 registry.
- tool_call 순서 보존.
- unknown tool, tool exception, LLM error, max_turns 처리.
- credentials resolver 주입.
- fake router 기반 테스트.

### 1차에서 제외

- Jido식 Signal/Directive 시스템.
- child/sub-agent spawn primitive.
- 외부 webhook/scheduler event 처리.
- 세션 JSONL 저장/branch/compaction.
- LiveView/PubSub 통합.
- Jido 정식 의존성 추가와 `use Jido.Agent` 매크로.
- 도구 권한 팝업/승인 UI.
- JSON Schema 검증 의존성. 필요하면 `Pado.Agent.Tool` 실행 함수 또는 Jido.Action 어댑터에서 검증한다.
- 최종 결과만 반환하는 편의 API. 스트리밍이 주 API다.

## 실행 순서

1. **Step 1: 순수 tool/result 함수** ✅
   - 🔴 Red: assistant content에서 tool_call을 순서대로 추출하는 테스트.
   - 🟢 Green: `ToolCalls.extract/1` 구현.
   - 🔵 Refactor: 중복 없이 pattern match 정리.

2. **Step 2: Tool wrapper/registry** ✅
   - 🔴 Red: `ToolRegistry.new/1`, `fetch/2`, `router_tools/1` 테스트.
   - 🟢 Green: name 기준 map과 router tool 변환 구현.
   - 🔵 Refactor: duplicate name 정책을 `{:error, {:duplicate_tool, name}}`로 확정.

3. **Step 3: ToolExecutor** ⚡
   - 🔴 Red: 성공, unknown tool, exception, timeout 결과가 `ToolResult`로 변환되는 테스트.
   - 🟢 Green: 순차 실행으로 먼저 통과.
   - 🔵 Refactor: `Task.async_stream(ordered: true)` 기반 concurrency 옵션 추가.

4. **Step 4: AssistantStream 소비기** ⚡
   - 🔴 Red: fake LLMRouter 이벤트 스트림을 넣으면 `message_start/update/end`가 emit되고 최종 Assistant를 반환하는 테스트.
   - 🟢 Green: `:done`/`:error` 최종 이벤트 중심 구현.
   - 🔵 Refactor: LLMRouter 이벤트명을 Agent 이벤트 payload로 안정화.

5. **Step 5: Loop.drive/2** ⚡
   - 🔴 Red: fake router가 tool_call → final answer 순서로 응답할 때 두 Turn이 돈다는 테스트.
   - 🟢 Green: max_turns와 tool loop 구현.
   - 🔵 Refactor: `RunState` 순수 helper로 상태 갱신 분리.

6. **Step 6: Loop.stream/1** ⚡
   - 🔴 Red: stream을 Enum으로 소비하면 `run_start`부터 `run_end`까지 순서가 맞는 테스트.
   - 🟢 Green: worker task + mailbox `Stream.resource` 구현.
   - 🔵 Refactor: consumer halt 시 worker abort/cleanup 추가.

7. **Step 7: Server 래퍼 초안** ⚡
   - 🔴 Red: `prompt/3`, `steer/3`, `follow_up/3`, `subscribe/2`, `abort/2` 상태 테스트.
   - 🟢 Green: GenServer로 busy reject와 큐 드레인 구현.
   - 🔵 Refactor: Jido 전환 가능성을 남기되 Signal/Directive는 추가하지 않는다.

## 리스크와 대응

- **Jido식 구조를 너무 일찍 도입할 위험**: 1차는 Pi식 직접 loop로 제한한다. signal/directive는 server wrapper 이후 실제 요구가 생길 때만 추가한다.
- **LLMRouter 이벤트에 partial assistant가 없다**: 1차 UI는 delta event를 직접 렌더한다. partial message가 필요해지면 별도 accumulator를 추가한다.
- **도구 schema 검증 부재**: 1차는 tool execute 함수 책임으로 두고, Jido.Action 어댑터 또는 JSON Schema validator는 실제 필요가 생길 때 추가한다.
- **크레덴셜 만료**: loop가 매 LLM Turn마다 `credential_fun`을 호출하게 해서 호출자 refresh 정책을 끼울 수 있게 한다.
- **서버 abort와 LLMRouter 취소**: 현재 LLMRouter stream opts에 abort signal이 없다. 1차는 consumer halt/worker kill로 처리하고, 필요하면 LLMRouter에 `:cancel_ref` 또는 `:abort` 옵션을 별도 커밋으로 추가한다.
- **이벤트 명칭 혼동**: core 이벤트는 `run_start/run_end`를 쓰고, Pi 호환이 필요하면 adapter에서 `agent_start/agent_end`로 변환한다.

## 완료 조건

- fake router 기반 테스트에서 `user → assistant(tool_call) → tool_result → assistant(final)` 루프가 통과한다.
- `Pado.Agent.Loop.stream/1`이 `run_start → turn_* → run_end` 이벤트 순서를 안정적으로 방출한다.
- unknown/failed tool도 LLM에 `ToolResult.error/3`로 전달되어 다음 Turn이 가능하다.
- 1차 구현에 Signal/Directive/Jido 의존성이 들어가지 않는다.
- `mix format`과 `mix compile --warnings-as-errors`가 통과한다.
