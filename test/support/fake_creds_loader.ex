defmodule Pado.Test.FakeCredsLoader do
  # 테스트용 Credential loader. 응답은 process dictionary :fake_creds_response에서 꺼낸다.
  # 매핑 인자는 무시. save 호출은 mailbox로 전달.

  def load(_arg) do
    Process.get(:fake_creds_response, {:error, :fake_creds_response_not_set})
  end

  def save(creds, _arg) do
    send(self(), {:fake_creds_save, creds})
    :ok
  end
end
