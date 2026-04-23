#!/bin/bash
# ChatGPT Codex 엔드포인트(/codex/responses) 수동 검증용 프로브.
#
# Elixir 어댑터를 짜기 전에 "헤더·바디 조합이 서버에 실제로 통하는지"를
# 순수 HTTP 레이어에서 확인하기 위한 스크립트다. 서버가 돌려주는 SSE
# 덩어리를 파일로 떨궈 이후 파서 구현·테스트 자산으로 쓴다.
#
# 사용:
#   ./scripts/codex_probe.sh <creds.json> [질문] [출력경로]
#
# 예:
#   mix pado.llm_router.login --output ~/.config/pado/openai.json
#   ./scripts/codex_probe.sh ~/.config/pado/openai.json "Say hello in one word."
#
# 기본 출력 경로는 /tmp/pado-codex-response.sse 이다.
# 응답은 stdout에도 스트리밍되므로 진행 상황을 실시간으로 볼 수 있다.

set -euo pipefail

CREDS_FILE="${1:-}"
QUERY="${2:-Say hello in one word.}"
OUTPUT="${3:-/tmp/pado-codex-response.sse}"
MODEL="${PADO_PROBE_MODEL:-gpt-5.1}"

if [[ -z "$CREDS_FILE" ]] || [[ ! -f "$CREDS_FILE" ]]; then
  cat <<USAGE >&2
사용법: $0 <creds.json> [질문] [출력경로]

creds.json 은 'mix pado.llm_router.login' 의 결과물(JSON)이다.
환경변수 PADO_PROBE_MODEL 로 모델 id를 덮어쓸 수 있다 (기본: gpt-5.1).
USAGE
  exit 1
fi

# --- 크레덴셜 파싱 (jq 가 있으면 jq, 없으면 python3) ---
if command -v jq >/dev/null 2>&1; then
  ACCESS=$(jq -r '.access' "$CREDS_FILE")
  ACCOUNT_ID=$(jq -r '.extra.account_id' "$CREDS_FILE")
  ORIGINATOR=$(jq -r '.extra.originator // "pi"' "$CREDS_FILE")
else
  eval "$(
    python3 - "$CREDS_FILE" <<'PYEOF'
import json, sys
with open(sys.argv[1]) as f:
    d = json.load(f)
print(f"ACCESS={d['access']}")
print(f"ACCOUNT_ID={d['extra']['account_id']}")
print(f"ORIGINATOR={d['extra'].get('originator', 'pi')}")
PYEOF
  )"
fi

if [[ -z "${ACCESS:-}" ]] || [[ -z "${ACCOUNT_ID:-}" ]]; then
  echo "creds.json 에서 access 또는 account_id 를 찾지 못했습니다." >&2
  exit 1
fi

SESSION_ID="probe-$(date +%s)-$$"

# --- 요청 바디 조립 (Pi 의 buildRequestBody 와 동일한 최소 형태) ---
BODY=$(
  python3 - "$QUERY" "$MODEL" "$SESSION_ID" <<'PYEOF'
import json, sys
query, model, session_id = sys.argv[1], sys.argv[2], sys.argv[3]
print(json.dumps({
    "model": model,
    "store": False,
    "stream": True,
    "instructions": "You are a helpful assistant.",
    "input": [
        {
            "role": "user",
            "content": [{"type": "input_text", "text": query}]
        }
    ],
    "text": {"verbosity": "medium"},
    "include": ["reasoning.encrypted_content"],
    "prompt_cache_key": session_id,
    "tool_choice": "auto",
    "parallel_tool_calls": True
}))
PYEOF
)

UA="pado-codex-probe ($(uname -s) $(uname -r); $(uname -m))"

echo "=> POST https://chatgpt.com/backend-api/codex/responses"
echo "=> 모델      : $MODEL"
echo "=> originator: $ORIGINATOR"
echo "=> session_id: $SESSION_ID"
echo "=> 저장 경로 : $OUTPUT"
echo "──────────────────────────────────────────────────────────"

# --- SSE 스트리밍 (-N: 버퍼링 끄고 즉시 출력) ---
curl -sS -N \
  -X POST "https://chatgpt.com/backend-api/codex/responses" \
  -H "Authorization: Bearer $ACCESS" \
  -H "chatgpt-account-id: $ACCOUNT_ID" \
  -H "originator: $ORIGINATOR" \
  -H "User-Agent: $UA" \
  -H "OpenAI-Beta: responses=experimental" \
  -H "accept: text/event-stream" \
  -H "content-type: application/json" \
  -H "session_id: $SESSION_ID" \
  -H "x-client-request-id: $SESSION_ID" \
  --data "$BODY" \
  | tee "$OUTPUT"

echo ""
echo "──────────────────────────────────────────────────────────"
echo "완료. 전체 응답이 $OUTPUT 에 저장되었습니다."
echo ""
echo "이벤트 타입별 개수:"
python3 - "$OUTPUT" <<'PYEOF'
import json, sys
from collections import Counter

counts = Counter()
with open(sys.argv[1]) as f:
    for line in f:
        if not line.startswith("data:"):
            continue
        data = line[5:].strip()
        if not data or data == "[DONE]":
            continue
        try:
            ev = json.loads(data)
            counts[ev.get("type", "(no type)")] += 1
        except json.JSONDecodeError:
            counts["(parse-error)"] += 1

for t, n in counts.most_common():
    print(f"  {n:>5}  {t}")
PYEOF
