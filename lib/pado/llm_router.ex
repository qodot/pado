defmodule Pado.LLMRouter do
  @moduledoc """
  LLM 프로바이더 API 클라이언트.

  모델(`Pado.LLMRouter.Model`)의 `:api` 필드를 보고 맞는 어댑터로
  디스패치한다. 어댑터 구현체는 `Pado.LLMRouter.Adapter` behaviour 를
  따른다.

  ## 공개 API

    * `stream_text/3` — 이벤트 Enumerable 반환.
    * `generate_text/3` — 스트림을 소비해 최종 Assistant 메시지 반환.

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

      {:ok, stream} = LLMRouter.stream_text(model, ctx, credentials: creds)
      Enum.each(stream, fn
        {:text_delta, %{delta: d}} -> IO.write(d)
        {:done, %{message: m}} -> IO.inspect(m.content)
        _ -> :ok
      end)
  """

  alias Pado.LLMRouter.{Context, Model}
  alias Pado.LLMRouter.Message.Assistant

  @adapters %{
    openai_codex_responses: Pado.LLMRouter.Providers.OpenAICodex.Responses
  }

  @doc """
  스트리밍 LLM 호출. 이벤트 Enumerable(`Pado.LLMRouter.Event.t/0`)을
  돌려준다.

  `opts`는 어댑터에 그대로 전달되며, 관용적으로 `:credentials` /
  `:api_key` / `:session_id` / `:reasoning_effort` 등을 받는다.

  어댑터를 찾지 못하면 `{:error, {:no_adapter, api}}`.
  """
  @spec stream_text(Model.t(), Context.t(), keyword) ::
          {:ok, Enumerable.t()} | {:error, term}
  def stream_text(%Model{api: api} = model, %Context{} = ctx, opts \\ []) do
    case Map.fetch(@adapters, api) do
      {:ok, adapter} -> adapter.stream_text(model, ctx, opts)
      :error -> {:error, {:no_adapter, api}}
    end
  end

  @doc """
  `stream_text/3`를 끝까지 소비해 최종 `Assistant` 메시지를 반환한다.

  중간 스트리밍 이벤트(토큰 단위 델타 등)가 필요하지 않은 호출자용
  동기 편의 함수. 실패 시 `{:error, reason}`.
  """
  @spec generate_text(Model.t(), Context.t(), keyword) ::
          {:ok, Assistant.t()} | {:error, term}
  def generate_text(%Model{} = model, %Context{} = ctx, opts \\ []) do
    with {:ok, stream} <- stream_text(model, ctx, opts) do
      collect_final(stream)
    end
  end

  defp collect_final(stream) do
    Enum.reduce_while(stream, {:error, :no_final_event}, fn
      {:done, %{message: m}}, _ -> {:halt, {:ok, m}}
      {:error, %{error_message: msg}}, _ -> {:halt, {:error, msg}}
      _, acc -> {:cont, acc}
    end)
  end
end
