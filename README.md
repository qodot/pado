# Pado 모노레포

`Pado`(파도)는 서버사이드 LLM 에이전트를 OTP 위에서 짓기 위한 Elixir 생태계다.
이 저장소는 Pado와 그 주변 패키지를 같이 두는 모노레포다.

## 패키지

| 디렉토리 | 역할 |
| --- | --- |
| [`pado/`](pado) | 핵심 라이브러리. LLM 프로바이더 클라이언트, 에이전트 루프, 이벤트 스트림. hex 배포 대상. |

추가 예정:

- `pado_kino/` — Livebook(Kino) 환경에서 Pado 에이전트를 시각화·인터랙션하기
  위한 헬퍼와 노트북 모음.
- `pado_web/` — Phoenix LiveView 위에서 Pado 에이전트를 1:1 사용자 세션으로
  띄우기 위한 바인딩.

## 구조 원칙

- **평평한 모노레포.** 각 패키지는 자기 `mix.exs`를 가지고, 서로는 `path:` 의존으로
  연결한다. umbrella(`apps/`)는 쓰지 않는다.
- **라이브러리는 프로세스를 소유하지 않는다.** Pado는 GenServer를 띄울 수 있는
  모듈을 제공할 수는 있어도, 시작·감독·수명은 호출자 앱이 결정한다.
- **상위 계층은 하위 계층의 인터페이스만 쓴다.** 예를 들어 `pado_kino`는
  `Pado.Agent.stream/2` 같은 공개 API만 사용하고, Pado 내부 구현에 의존하지 않는다.

## 작업 규칙

저장소 전체에 적용되는 작업 규칙은 [`AGENTS.md`](AGENTS.md)에 있다. 주요 항목:

- 문서·주석·커밋 메시지는 한국어
- 코드 식별자는 영어
- `mix format`과 `mix compile --warnings-as-errors` 통과 필수
- 한 커밋에 한 가지 맥락만

## 빠른 시작

라이브러리 빌드와 테스트:

```bash
cd pado
mix deps.get
mix test
```

각 패키지는 자기 디렉토리 안에서 `mix` 명령을 돌린다.
