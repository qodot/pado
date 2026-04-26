defmodule Pado.LLMRouter.Providers.OpenAICodex do
  @behaviour Pado.LLMRouter.Provider

  alias Pado.LLMRouter.{Context, Model}
  alias Pado.LLMRouter.Stream, as: RouterStream
  alias Pado.LLMRouter.OAuth.Credentials
  alias Pado.LLMRouter.Providers.OpenAICodex.{EventMapper, Request, SSE}

  @finch_pool Req.Finch
  @default_receive_timeout 300_000

  @impl true
  def stream(
        %Model{provider: :openai_codex} = model,
        %Context{} = ctx,
        %Credentials{
          provider: :openai_codex,
          access: access,
          extra: %{"account_id" => account_id}
        },
        session_id,
        opts
      ) do
    url = Request.endpoint_url(model)
    headers = Request.build_headers(access, account_id, session_id, opts)
    body = Request.build_body(model, ctx, session_id, opts) |> Jason.encode!()

    stream = open_stream(url, headers, body, model, opts)
    {:ok, stream}
  end

  def stream(
        %Model{provider: :openai_codex},
        _ctx,
        %Credentials{provider: :openai_codex},
        _session_id,
        _opts
      ),
      do: {:error, :missing_account_id}

  def stream(
        %Model{provider: :openai_codex},
        _ctx,
        %Credentials{provider: provider},
        _session_id,
        _opts
      ),
      do: {:error, {:wrong_provider_credentials, provider}}

  def stream(%Model{provider: provider}, _ctx, _credentials, _session_id, _opts),
    do: {:error, {:unsupported_provider, provider}}

  defp open_stream(url, headers, body, model, opts) do
    receive_timeout = Keyword.get(opts, :receive_timeout, @default_receive_timeout)

    request = Finch.build(:post, url, headers, body)
    ref = Finch.async_request(request, @finch_pool)

    events =
      ref
      |> data_stream(receive_timeout)
      |> SSE.stream()
      |> EventMapper.map_stream(model)

    %RouterStream{events: events, cancel: fn -> Finch.cancel_async_request(ref) end}
  end

  defp data_stream(ref, timeout) do
    Stream.resource(
      fn -> %{ref: ref, timeout: timeout, phase: :status, halted: false} end,
      &next_chunk/1,
      fn %{ref: ref} ->
        _ = Finch.cancel_async_request(ref)
        :ok
      end
    )
  end

  defp next_chunk(%{halted: true} = s), do: {:halt, s}

  defp next_chunk(%{phase: :status, ref: ref, timeout: timeout} = s) do
    receive do
      {^ref, {:status, 200}} ->
        {[], %{s | phase: :data}}

      {^ref, {:status, status}} ->
        body = drain_error_body(ref, timeout)
        {[stream_error_chunk("HTTP #{status}: #{body}")], %{s | halted: true}}

      {^ref, {:error, reason}} ->
        {[stream_error_chunk("transport error: #{inspect(reason)}")], %{s | halted: true}}
    after
      timeout ->
        {[stream_error_chunk("transport error: :await_status_timeout")], %{s | halted: true}}
    end
  end

  defp next_chunk(%{phase: :data, ref: ref, timeout: timeout} = s) do
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
end
