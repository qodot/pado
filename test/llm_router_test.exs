defmodule Pado.LLMRouterTest do
  use ExUnit.Case, async: true

  alias Pado.LLMRouter
  alias Pado.LLMRouter.{Catalog, Context, Model}
  alias Pado.LLMRouter.Message.User
  alias Pado.LLMRouter.OAuth.Credentials

  test "알 수 없는 API는 어댑터 없음 오류를 반환한다" do
    model = %Model{id: "dummy", provider: :dummy}
    ctx = Context.new()

    assert {:error, {:unsupported_provider, :dummy}} = LLMRouter.stream(model, ctx)
    assert {:error, {:unsupported_provider, :dummy}} = LLMRouter.stream(model, ctx)
  end

  test "OpenAI Codex 어댑터는 크레덴셜을 사전 검증한다" do
    model = Catalog.OpenAICodex.default()
    ctx = Context.new(messages: [User.new("안녕")])

    assert {:error, :missing_credentials} = LLMRouter.stream(model, ctx)

    wrong_provider = Credentials.build(:other_provider, "access", "refresh", 3600)

    assert {:error, {:wrong_provider_credentials, :other_provider}} =
             LLMRouter.stream(model, ctx, credentials: wrong_provider)

    missing_account_id = Credentials.build(:openai_codex, "access", "refresh", 3600)

    assert {:error, :missing_account_id} =
             LLMRouter.stream(model, ctx, credentials: missing_account_id)
  end
end
