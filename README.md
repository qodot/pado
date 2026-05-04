# Pado

<img width="600" height="600" alt="pado" src="https://github.com/user-attachments/assets/1609ee6d-6420-4add-9e2a-30b791917248" />


`pado`(한국어로 wave라는 뜻이고 발음은 '파도'입니다)는 [pi](https://github.com/badlogic/pi-mono)와 [jido](https://github.com/agentjido/jido)에서 영감을 받은(합쳐서 pado) 에이전트 런타임 및 하네스 라이브러리입니다.

이 저장소는 `pado`와 그 주변 패키지를 한곳에 모아 함께 키우는 모노레포입니다. 처음 오신 분은 [`pado/`](pado) 패키지의 README부터 읽어보시기 바랍니다. 라이브러리 사용법과 현재 구현 상태가 거기에 정리되어 있습니다.

## 패키지

- [`pado/`](pado) — 에이전트 백엔드 라이브러리 + 런타임입니다.
- `pado_kino/` *(예정)* — Livebook(Kino) 환경에서 Pado 에이전트를 띄우기 위한 헬퍼입니다.
- `pado_web/` *(예정)* — Phoenix LiveView 위에서 Pado 에이전트를 사용자 세션으로 띄우기 위한 바인딩입니다.

## 빠른 시작

```bash
cd pado
mix deps.get
mix test
```

각 패키지는 자기 디렉토리 안에서 `mix` 명령을 돌립니다.

## 작업 규칙

저장소 전체에 적용되는 규칙은 [`AGENTS.md`](AGENTS.md)에 있습니다. 핵심만 추리면 다음과 같습니다.

- 문서·주석·커밋 메시지는 한국어, 코드 식별자는 영어로 씁니다.
- `mix format`과 `mix compile --warnings-as-errors`를 반드시 통과해야 합니다.
- 한 커밋에 한 가지 맥락만 담습니다.

## 라이선스

MIT.
