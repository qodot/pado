defmodule Pado.Test.FakeLLMRouter do
  # 테스트용 LLMRouter 대체. 호출 인자는 호출 프로세스 mailbox로 보내고,
  # 응답은 process dictionary :fake_router_response 에서 꺼낸다.

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

    Process.get(:fake_router_response, {:error, :fake_router_response_not_set})
  end
end
