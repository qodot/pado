defmodule Pado.LLMTest do
  use ExUnit.Case, async: true

  alias Pado.LLM
  alias Pado.LLM.{Catalog, Context, Model, Stream}
  alias Pado.LLM.Message.User
  alias Pado.LLM.Credential.OAuth.Credentials

  test "알 수 없는 API는 어댑터 없음 오류를 반환한다" do
    model = %Model{id: "dummy", provider: :dummy}
    ctx = Context.new()

    credentials = Credentials.build(:openai_codex, "access", "refresh", 3600)

    assert {:error, {:unsupported_provider, :dummy}} =
             LLM.stream(model, ctx, credentials, "session-1")

    assert {:error, {:unsupported_provider, :dummy}} =
             LLM.stream(model, ctx, credentials, "session-1")
  end

  test "Stream 구조체는 취소 함수를 가진다" do
    parent = self()

    stream = %Stream{
      events: [],
      cancel: fn ->
        send(parent, :cancelled)
        :ok
      end
    }

    assert :ok == stream.cancel.()
    assert_received :cancelled
  end

  test "Stream 구조체는 이벤트 Enumerable로 동작한다" do
    stream = %Stream{events: [:a, :b], cancel: fn -> :ok end}

    assert Enum.to_list(stream) == [:a, :b]
  end

  test "OpenAI Codex 어댑터는 크레덴셜을 사전 검증한다" do
    model = Catalog.OpenAICodex.default()
    ctx = Context.new(messages: [User.new("안녕")])

    wrong_provider = Credentials.build(:other_provider, "access", "refresh", 3600)

    assert {:error, {:wrong_provider_credentials, :other_provider}} =
             LLM.stream(model, ctx, wrong_provider, "session-1")

    missing_account_id = Credentials.build(:openai_codex, "access", "refresh", 3600)

    assert {:error, :missing_account_id} =
             LLM.stream(model, ctx, missing_account_id, "session-1")
  end
end
