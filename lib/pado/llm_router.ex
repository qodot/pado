defmodule Pado.LLMRouter do
  @moduledoc """
  LLM 프로바이더 API 클라이언트.

  모델(`Pado.LLMRouter.Model`)의 `:api` 필드를 보고 맞는 어댑터로
  디스패치한다. 어댑터 구현체는 `Pado.LLMRouter.Adapter` behaviour 를
  따른다.

  ## 공개 API

    * `stream/3` — 이벤트 Enumerable 반환.

  ## 예

      alias Pado.LLMRouter
      alias Pado.LLMRouter.{Context, Catalog}
      alias Pado.LLMRouter.Message.User
      alias Pado.LLMRouter.OAuth.Credentials

      {:ok, creds} =
        "~/.config/pado/openai.json"
        |> Path.expand()
        |> File.read!()
        |> Jason.decode!()
        |> Credentials.from_map()

      model = Catalog.OpenAICodex.default()
      ctx = Context.new(messages: [User.new("안녕")])

      {:ok, stream} = LLMRouter.stream(model, ctx, credentials: creds)
      Enum.each(stream, fn
        {:text_delta, %{delta: d}} -> IO.write(d)
        {:done, %{message: m}} -> IO.inspect(m.content)
        _ -> :ok
      end)
  """

  alias Pado.LLMRouter.{Context, Model}

  @provider_map %{
    openai_codex: Pado.LLMRouter.Providers.OpenAICodex
  }

  @doc """
  스트리밍 LLM 호출. 이벤트 Enumerable(`Pado.LLMRouter.Event.t/0`)을
  돌려준다.

  `opts`는 어댑터에 그대로 전달되며, 관용적으로 `:credentials` /
  `:api_key` / `:session_id` / `:reasoning_effort` 등을 받는다.

  프로바이더를 지원하지 않으면 `{:error, {:unsupported_provider, provider}}`.
  """
  @spec stream(Model.t(), Context.t(), keyword) ::
          {:ok, Enumerable.t()} | {:error, term}
  def stream(%Model{provider: provider} = model, %Context{} = ctx, opts \\ []) do
    case Map.fetch(@provider_map, provider) do
      {:ok, adapter} -> adapter.stream(model, ctx, opts)
      :error -> {:error, {:unsupported_provider, provider}}
    end
  end
end
