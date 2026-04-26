defmodule Pado.LLMRouter.Providers.OpenAICodex do
  @moduledoc """
  ChatGPT Codex `/codex/responses` 엔드포인트용 어댑터.

  `Pado.LLMRouter.Adapter` 구현체. 이 모듈이 하는 일:

    1. 크레덴셜·account_id 추출.
    2. `Request`로 URL·헤더·바디 조립.
    3. `Finch.async_request/2`로 비동기 HTTP 요청.
    4. `Stream.resource`로 청크 메시지를 Enumerable 바이너리로 변환.
    5. `SSE.stream/1` → `EventMapper.map_stream/2` 파이프로
       `Pado.LLMRouter.Event` 튜플 스트림 반환.

  Finch 풀은 Req가 이미 띄운 `Req.Finch`를 재사용한다. 별도 Supervisor
  설정이 필요 없다.

  ## 오류 흐름

    * 크레덴셜 누락·잘못된 provider 등 사전 검증 실패 → `{:error, reason}`
    * HTTP 상태 non-2xx → 응답 바디를 모아서 `{:error, _}` 이벤트 **하나**만
      담은 스트림
    * Finch 전송 실패 → 같은 방식으로 `{:error, _}` 이벤트 하나

  2xx 스트림 도중의 예외(타임아웃 등)는 Stream 소비자 쪽으로 raise 된다.
  재시도는 에이전트 레이어(Pado.Agent) 책임이다.
  """

  @behaviour Pado.LLMRouter.Adapter

  alias Pado.LLMRouter.{Context, Model, Usage}
  alias Pado.LLMRouter.Message.Assistant
  alias Pado.LLMRouter.OAuth.Credentials
  alias Pado.LLMRouter.Providers.OpenAICodex.{EventMapper, Request, SSE}

  @finch_pool Req.Finch
  @default_receive_timeout 300_000

  @impl true
  def supports?(%Model{provider: :openai_codex}), do: true
  def supports?(_), do: false

  @impl true
  def stream(%Model{provider: :openai_codex} = model, %Context{} = ctx, opts)
      when is_list(opts) do
    opts = Request.ensure_session_id(opts)

    with {:ok, creds} <- fetch_credentials(opts),
         {:ok, account_id} <- fetch_account_id(creds) do
      url = Request.endpoint_url(model)
      headers = Request.build_headers(creds.access, account_id, opts)
      body = model |> Request.build_body(ctx, opts) |> Jason.encode!()

      stream = open_stream(url, headers, body, model, opts)
      {:ok, stream}
    end
  end

  def stream(%Model{id: id}, _ctx, _opts),
    do: {:error, {:unsupported_model, id}}

  defp fetch_credentials(opts) do
    case Keyword.get(opts, :credentials) do
      %Credentials{provider: :openai_codex} = c -> {:ok, c}
      %Credentials{provider: p} -> {:error, {:wrong_provider_credentials, p}}
      _ -> {:error, :missing_credentials}
    end
  end

  defp fetch_account_id(%Credentials{extra: %{"account_id" => id}}) when is_binary(id),
    do: {:ok, id}

  defp fetch_account_id(_), do: {:error, :missing_account_id}

  defp open_stream(url, headers, body, model, opts) do
    receive_timeout = Keyword.get(opts, :receive_timeout, @default_receive_timeout)

    request = Finch.build(:post, url, headers, body)
    ref = Finch.async_request(request, @finch_pool)

    case await_status(ref, receive_timeout) do
      {:ok, 200} ->
        ref
        |> data_stream(receive_timeout)
        |> SSE.stream()
        |> EventMapper.map_stream(model)

      {:ok, status} ->
        body = drain_error_body(ref, receive_timeout)
        _ = Finch.cancel_async_request(ref)
        [http_error_event(model, status, body)]

      {:error, reason} ->
        _ = Finch.cancel_async_request(ref)
        [transport_error_event(model, reason)]
    end
  end

  defp await_status(ref, timeout) do
    receive do
      {^ref, {:status, status}} -> {:ok, status}
      {^ref, {:error, reason}} -> {:error, reason}
    after
      timeout -> {:error, :await_status_timeout}
    end
  end

  defp data_stream(ref, timeout) do
    Stream.resource(
      fn -> %{ref: ref, timeout: timeout, halted: false} end,
      fn
        %{halted: true} = s ->
          {:halt, s}

        %{ref: ref, timeout: timeout} = s ->
          receive do
            {^ref, {:headers, _}} ->
              {[], s}

            {^ref, {:data, chunk}} ->
              {[chunk], s}

            {^ref, :done} ->
              {:halt, %{s | halted: true}}

            {^ref, {:error, reason}} ->
              {[stream_error_chunk("Finch 스트림 오류: #{inspect(reason)}")], %{s | halted: true}}
          after
            timeout -> {[stream_error_chunk("Finch 스트림 시간 초과")], %{s | halted: true}}
          end
      end,
      fn %{ref: ref} ->
        _ = Finch.cancel_async_request(ref)
        :ok
      end
    )
  end

  defp drain_error_body(ref, timeout), do: drain_error_body(ref, timeout, [])

  defp drain_error_body(ref, timeout, acc) do
    receive do
      {^ref, {:headers, _}} -> drain_error_body(ref, timeout, acc)
      {^ref, {:data, chunk}} -> drain_error_body(ref, timeout, [chunk | acc])
      {^ref, :done} -> finalize_body(acc)
      {^ref, {:error, _}} -> finalize_body(acc)
    after
      timeout -> finalize_body(acc)
    end
  end

  defp finalize_body(acc), do: acc |> Enum.reverse() |> IO.iodata_to_binary()

  defp stream_error_chunk(message) do
    data = Jason.encode!(%{"type" => "error", "message" => message})
    "data: " <> data <> "\n\n"
  end

  defp http_error_event(model, status, body) do
    msg = "HTTP #{status}: #{body}"
    assistant = %{Assistant.init(model) | stop_reason: :error, error_message: msg}

    {:error,
     %{
       reason: :error,
       error_message: msg,
       message: assistant,
       usage: Usage.empty()
     }}
  end

  defp transport_error_event(model, reason) do
    msg = "transport error: #{inspect(reason)}"
    assistant = %{Assistant.init(model) | stop_reason: :error, error_message: msg}

    {:error,
     %{
       reason: :error,
       error_message: msg,
       message: assistant,
       usage: Usage.empty()
     }}
  end
end
