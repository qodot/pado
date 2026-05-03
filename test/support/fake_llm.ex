defmodule Pado.Test.FakeLLM do
  # 테스트용 LLM 대체. 호출 인자는 호출 프로세스 mailbox로 보내고,
  # 응답은 두 모드 중 하나로 제공한다:
  #   - :fake_router_responses (큐)  — 매 호출마다 head 꺼냄 (multi-turn 테스트용)
  #   - :fake_router_response (단일) — 모든 호출에 같은 응답 (큐가 비었을 때 폴백)

  def stream(model, ctx, creds, session_id, opts) do
    send(
      self(),
      {:fake_router_called,
       %{
         model: model,
         ctx: ctx,
         creds: creds,
         session_id: session_id,
         opts: opts
       }}
    )

    case Process.get(:fake_router_responses) do
      [head | rest] ->
        Process.put(:fake_router_responses, rest)
        head

      _ ->
        Process.get(:fake_router_response, {:error, :fake_router_response_not_set})
    end
  end
end
