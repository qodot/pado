# Pado

<img width="600" height="600" alt="pado" src="https://github.com/user-attachments/assets/1609ee6d-6420-4add-9e2a-30b791917248" />


`pado`(한국어로 wave라는 뜻이고 발음은 '파도'입니다)는 [pi](https://github.com/badlogic/pi-mono)와 [jido](https://github.com/agentjido/jido)에서 영감을 받은(합쳐서 pado) 에이전트 런타임 및 하네스 라이브러리입니다.

`pado`는 `pi`처럼 최소한의 프리셋만 가지는 대신, 사용자가 필요한 부분만 쉽게 확장할 수 있게 도와줍니다. 또 `jido`처럼 배포시 런타임 구성(서브/멀티 에이전트, 툴 병렬 실행 등의 프로세스 관리)을 도와줍니다. 별도의 복잡한 인프라 컴포넌트를 구성하지 않아도 됩니다.

이 저장소는 `pado`와 그 주변 패키지를 한곳에 모아 함께 키우는 모노레포입니다. 처음 오신 분은 [`pado/`](pado) 패키지의 README부터 읽어보시기 바랍니다. 라이브러리 사용법과 현재 구현 상태가 거기에 정리되어 있습니다.

## 패키지

- [`pado/`](pado) — 에이전트 백엔드 라이브러리 + 런타임입니다.
- [`pado_kino/`](pado_kino) — Livebook(Kino) 환경에서 Pado 에이전트를 띄우기 위한 헬퍼와 예제 노트북 모음입니다.
- `pado_web/` *(예정)* — Phoenix LiveView 위에서 Pado 에이전트를 사용자 세션으로 띄우기 위한 바인딩입니다.

## Livebook에서 실행

[`pado_kino`](pado_kino)는 `pado`를 Livebook 위에서 실험할 수 있게 묶어 놓은 패키지입니다. `pado` + `kino`를 의존성으로 끌어오고, 바로 열 수 있는 예제 노트북을 함께 제공합니다.

현재 들어 있는 노트북:

- [`pado_kino/livebooks/pado_chat.livemd`](pado_kino/livebooks/pado_chat.livemd) — Pado 에이전트와 대화하는 채팅 UI 노트북입니다.

Livebook이 설치되어 있다면 다음과 같이 엽니다.

```bash
livebook server pado_kino/livebooks/pado_chat.livemd
```

노트북은 `Mix.install`로 같은 저장소의 `pado`와 `pado_kino`를 경로 의존성으로 가져오므로, 저장소를 클론한 상태에서 그대로 동작합니다. OpenAI Codex 등 OAuth가 필요한 프로바이더는 노트북 안내에 따라 미리 `mix pado.llm.login`으로 크레덴셜을 만들어 두면 됩니다.
