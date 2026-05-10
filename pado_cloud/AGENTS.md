# Pado Cloud 작업 지침

이 프로젝트는 Phoenix LiveView 기반 Pado SaaS 웹 클라이언트입니다.

## 기본 규칙

- 작업 완료 전 `mix precommit`을 실행하고 실패를 수정한다.
- HTTP 요청에는 이미 포함된 `Req`를 사용한다.
- 새 LiveView 템플릿은 `<Layouts.app flash={@flash} ...>`로 감싼다.
- 폼 입력은 가능한 한 `core_components.ex`의 `<.input>`을 사용한다.
- 아이콘은 `<.icon>` 컴포넌트를 사용한다.
- Tailwind CSS v4의 `app.css` import 구조를 유지한다.
- 원시 CSS에서 `@apply`를 사용하지 않는다.
- 템플릿 안에 인라인 `<script>`를 새로 추가하지 않는다.
- 테스트에서 프로세스를 시작할 때는 `start_supervised!/1`을 우선 사용한다.
- 비동기 처리는 `Process.sleep/1` 대신 모니터링이나 `_ = :sys.get_state/1`로 동기화한다.
