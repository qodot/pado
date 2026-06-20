# pado_web 프로젝트 이름 변경

> 생성일: 2026-06-21 00:37
> 상태: 실행 완료

## 개요

`pado_web` Mix app의 이름을 로컬 단일 사용자 앱 성격에 맞게 `pado_local`로 바꾼다. 기능 동작은 바꾸지 않고 앱 이름, 모듈 네임스페이스, 경로 참조만 함께 정리한다.

## 확인한 사실

- 현재 앱 디렉터리는 `pado_web/`이다.
- 현재 Mix app atom은 `:pado_web`이다.
- 현재 모듈 prefix는 `PadoWeb`, web 모듈 prefix는 `PadoWebWeb`이다.
- config, 테스트, asset build alias가 모두 `pado_web` 이름을 참조한다.

## 변경 범위

- `pado_web/` 디렉터리를 `pado_local/`로 이동한다.
- `:pado_web` 참조를 `:pado_local`로 바꾼다.
- `PadoWeb`/`PadoWebWeb` 모듈 prefix를 `PadoLocal`/`PadoLocalWeb`으로 바꾼다.
- `lib/pado_web*`, `test/pado_web_web*` 경로를 새 이름에 맞춰 이동한다.
- README의 프로젝트 목록 경로를 갱신한다.

## 건드리지 않을 범위

- LiveView UI 동작, 라우트, session 저장 모델은 바꾸지 않는다.
- `pado`, `pado_cloud`, `pado_kino` 앱의 기능 코드는 바꾸지 않는다.
- 새 추상화나 호환 shim은 만들지 않는다.

## 실행 순서

1. 브랜치를 만든다.
2. 디렉터리와 파일 경로를 이동한다.
3. 이름 참조를 기계적으로 치환한다.
4. `mix format`을 실행한다.
5. `mix compile --warnings-as-errors`와 `mix precommit`으로 검증한다.
6. 변경을 커밋하고 push한 뒤 PR을 만든다.
