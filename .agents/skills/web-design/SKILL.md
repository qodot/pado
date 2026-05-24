---
name: web-design
description: Pado Web의 Phoenix LiveView 화면, 컴포넌트, 디자인 시스템을 만들거나 수정할 때 사용한다. daisyUI 컴포넌트를 적극 사용하고 공통 UI는 PadoWebWeb.DesignSystem에 둔다.
---

# web-design

## 목적

Pado Web UI를 로컬 단일 사용자 에이전트 작업대답게 만든다. 마케팅 랜딩 페이지보다 바로 쓸 수 있는 작업 화면을 우선한다.

## 기본 원칙

- `pado_web`의 UI 작업에만 적용한다.
- Phoenix LiveView와 기존 Tailwind v4, daisyUI 구성을 유지한다.
- daisyUI 컴포넌트를 디자인 시스템의 기본 빌딩 블록으로 적극 사용한다.
- 임의 Tailwind 조합은 레이아웃, 간격, 반응형 보정에만 사용한다.
- end 사용자에게 보이는 텍스트는 영어로 쓴다.
- 문서, 주석, docstring은 한국어로 쓴다.

## 컴포넌트 규칙

- 새 공통 UI는 `pado_web/lib/pado_web_web/components/design_system.ex`의 `PadoWebWeb.DesignSystem`에 추가한다.
- `core_components.ex`에는 새 컴포넌트를 추가하거나 기존 컴포넌트를 수정하지 않는다.
- 필요하면 `pado_web_web.ex`에서 `PadoWebWeb.DesignSystem`을 import한다.
- 기존 `CoreComponents`는 이미 있는 `<.input>`, `<.flash>` 같은 Phoenix 기본 컴포넌트를 재사용할 때만 쓴다.
- 반복되는 daisyUI 패턴은 함수 컴포넌트나 LiveComponent로 감싼다.
- 상태와 이벤트가 없는 작은 UI는 함수 컴포넌트로 만든다.
- 상태, 이벤트, 스트리밍, 선택 상태가 있는 UI는 LiveComponent로 만든다.

## daisyUI 사용법

- 버튼, 입력, 배지, 상태, alert, modal, drawer, tabs, menu, dropdown, chat bubble, skeleton, loading, progress, table은 daisyUI 컴포넌트를 먼저 검토한다.
- 컴포넌트 API는 Pado Web 의미를 드러내게 만든다. 예: `variant`, `size`, `status`, `active`.
- 호출부에 daisyUI 클래스가 반복되면 DesignSystem 컴포넌트로 올린다.
- `class` 속성은 필요할 때 마지막 보정 수단으로만 열어 둔다.
- 정확한 클래스나 구조가 불확실하면 공식 daisyUI 문서를 확인한다.

## 화면 설계 기준

- 채팅, 실행 로그, provider 선택, 작업 상태, 스레드 탐색 같은 실제 작업 흐름을 첫 화면에서 우선한다.
- SaaS 계정, 결제, 조직 관리 기능은 `pado_cloud` 책임으로 둔다.
- 카드 안에 카드를 중첩하지 않는다.
- 조용하고 밀도 있는 운영 도구 톤을 유지한다.
- 텍스트와 컨트롤이 모바일과 데스크톱에서 겹치지 않게 확인한다.

## 검증

- 변경 후 `mix format`과 `mix compile --warnings-as-errors`를 실행한다.
- 가능하면 `mix precommit`까지 실행한다.
- 시각 변경이 있으면 로컬 서버를 띄우고 브라우저로 주요 화면을 확인한다.
