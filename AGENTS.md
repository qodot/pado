# LLMRouter 프로젝트 지침

이 문서는 이 저장소에서 작업하는 에이전트·사용자 모두에게 적용된다.

## 언어

- **모든 문서·주석·커밋 메시지는 한국어로 작성한다.**
  - `@moduledoc`, `@doc`, `@typedoc` 포함.
  - 일반 `#` 주석 포함.
  - `README.md`, `AGENTS.md`, `CHANGELOG.md` 등 저장소에 체크인되는 모든 마크다운 문서 포함.
  - 커밋 메시지 subject/body 전부 한국어.
- **코드 식별자는 영어**를 유지한다. 모듈·함수·변수·타입·아톰·파라미터·에러 리즌 키워드는 전부 영어.
- **에러 메시지/로그**는 사용자 출력 여부로 판단한다.
  - CLI에서 사용자에게 보여지는 메시지(`Mix.shell().info/error`, `IO.puts` 등): 한국어.
  - `raise`/`Logger`로 나가는 개발자 대상 메시지: 한국어. 단 디버깅 편의상 `inspect/1`로 붙는 구조화된 값은 그대로.

## 커밋 메시지

- Conventional Commits 스타일 prefix(`feat:`, `fix:`, `refactor:`, `docs:`, `test:`, `chore:`)는 유지하되, 뒤의 설명은 한국어로 쓴다.
  - 예: `feat: OpenAI Codex OAuth 로그인 초안 추가`
  - 예: `fix: refresh 토큰 로테이션 시 extra 필드 누락 수정`
- 본문이 필요하면 72자 줄바꿈을 맞추되 내용은 한국어로.

## 커밋 단위

- **한 커밋에 한 가지 맥락만 담는다.** 여러 파일이 바뀌어도 같은 의도면 한 커밋이고, 같은 파일 안이라도 서로 무관한 변경이면 별개 커밋이다.
- 큰 변경은 의도 단위로 쪼개 순서대로 푸시한다. 예:
  1. `feat: Credentials 구조체 추가`
  2. `feat: PKCE 헬퍼 추가`
  3. `feat: OpenAICodex 로그인 플로우 구현`
- **포매팅/리팩터/기능 추가를 섞지 않는다.** 순수 포맷 변경은 `style:` 또는 `chore: format` 단독 커밋.
- WIP·덩어리 커밋은 지양한다. 필요하면 `git add -p`로 헝크 단위 선택.
- 작업 중 깨진 상태를 저장할 때는 별도 브랜치에서만 허용하고, 머지 전에 `git rebase -i`로 정리한다.

## 코드 스타일

- `mix format`을 반드시 통과해야 한다.
- `mix compile --warnings-as-errors`가 통과해야 한다.
- 공개 API에는 `@spec`와 `@doc`을 한국어로 작성한다.
- 내부 함수에도 동기(왜 이 로직이 필요한지)는 주석으로 남긴다.

## OAuth / 크레덴셜 취급

- 라이브러리는 **어떤 영속 저장소도 소유하지 않는다.** 로그인 결과는 호출자에게 `%LLMRouter.OAuth.Credentials{}`로 반환만 한다.
- 테스트·스크립트·문서 안에 **실제 토큰을 절대 커밋하지 않는다.** 샘플이 필요하면 명백히 합성된 더미(`"access_xxx"`, `"refresh_yyy"` 등)를 쓴다.
- `refresh/1` 호출 결과는 항상 새 `%Credentials{}`를 돌려주며, 저장소 갱신(로테이션)은 호출자 책임임을 문서에 명시한다.

## 참고 프로젝트

- `@mariozechner/pi-ai` (TypeScript) — OAuth 플로우와 프로바이더 어댑터의 레퍼런스 구현.
- `req_llm` (Elixir) — 통합 LLM 클라이언트의 Elixir 관용 구현.

새로운 프로바이더나 기능을 추가할 때는 위 두 프로젝트의 해당 부분을 먼저 읽고, 어디에서 갈라지고 왜 갈라지는지 커밋 메시지나 `@moduledoc`에 남긴다.
