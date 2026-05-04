# pado_kino

[Pado](../pado) 에이전트를 Livebook(Kino) 환경에서 시각화·인터랙션하기 위한
헬퍼와 노트북 모음입니다.

## 사용

Livebook 노트북에서 `Mix.install`로 의존합니다.

```elixir
Mix.install([
  {:pado_kino, path: "/abs/path/pado/pado_kino"}
])
```

`pado_kino`는 내부적으로 `pado`와 `kino`를 의존성으로 끌어옵니다.

## 개발

```bash
cd pado_kino
mix deps.get
mix test
```
