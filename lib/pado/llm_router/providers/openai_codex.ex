defmodule Pado.LLMRouter.Providers.OpenAICodex do
  @behaviour Pado.LLMRouter.Provider

  alias Pado.LLMRouter.{Context, Model}
  alias Pado.LLMRouter.Stream, as: RouterStream
  alias Pado.LLMRouter.OAuth.Credentials
  alias Pado.LLMRouter.Providers.OpenAICodex.{EventMapper, Request, SSE}

  @finch_pool Req.Finch
  @default_receive_timeout 300_000
  @default_max_retries 3
  @default_retry_delay_ms 1_000

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
    max_retries = Keyword.get(opts, :max_retries, @default_max_retries)
    retry_delay_ms = Keyword.get(opts, :retry_delay_ms, @default_retry_delay_ms)
    request = Finch.build(:post, url, headers, body)

    case start_request(request, receive_timeout, max_retries, retry_delay_ms) do
      {:ok, ref} ->
        events =
          ref
          |> data_stream(receive_timeout)
          |> SSE.stream()
          |> EventMapper.map_stream(model)

        %RouterStream{events: events, cancel: fn -> cancel_ref(ref) end}

      {:error, chunk} ->
        events = [chunk] |> SSE.stream() |> EventMapper.map_stream(model)
        %RouterStream{events: events, cancel: fn -> :ok end}
    end
  end

  defp start_request(request, timeout, max_retries, retry_delay_ms) do
    do_start_request(request, timeout, max_retries, retry_delay_ms, 0)
  end

  defp do_start_request(request, timeout, max_retries, retry_delay_ms, attempt) do
    ref = Finch.async_request(request, @finch_pool)

    receive do
      {^ref, {:status, 200}} ->
        {:ok, ref}

      {^ref, {:status, status}} ->
        {body, headers} = drain_error_response(ref, timeout)
        message = "HTTP #{status}: #{body}"

        if retryable_status?(status) and attempt < max_retries do
          sleep_before_retry(retry_delay_ms, attempt, retry_after_ms(headers))
          do_start_request(request, timeout, max_retries, retry_delay_ms, attempt + 1)
        else
          {:error, stream_error_chunk(message)}
        end

      {^ref, {:error, reason}} ->
        retry_transport_or_error(request, timeout, max_retries, retry_delay_ms, attempt, reason)
    after
      timeout ->
        cancel_ref(ref)

        retry_transport_or_error(
          request,
          timeout,
          max_retries,
          retry_delay_ms,
          attempt,
          :await_status_timeout
        )
    end
  end

  defp retry_transport_or_error(request, timeout, max_retries, retry_delay_ms, attempt, reason) do
    if retryable_transport?(reason) and attempt < max_retries do
      sleep_before_retry(retry_delay_ms, attempt, nil)
      do_start_request(request, timeout, max_retries, retry_delay_ms, attempt + 1)
    else
      {:error, stream_error_chunk("transport error: #{inspect(reason)}")}
    end
  end

  defp sleep_before_retry(_base, _attempt, ms) when is_integer(ms) and ms > 0,
    do: Process.sleep(ms)

  defp sleep_before_retry(base, attempt, _ms) do
    delay = trunc(base * :math.pow(2, attempt))
    if delay > 0, do: Process.sleep(delay)
  end

  defp cancel_ref(ref) do
    _ = Finch.cancel_async_request(ref)
    :ok
  end

  defp data_stream(ref, timeout) do
    Stream.resource(
      fn -> %{ref: ref, timeout: timeout, halted: false} end,
      &next_chunk/1,
      fn %{ref: ref} -> cancel_ref(ref) end
    )
  end

  defp next_chunk(%{halted: true} = s), do: {:halt, s}

  defp next_chunk(%{ref: ref, timeout: timeout} = s) do
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

  defp retryable_status?(status), do: status in [429, 500, 502, 503, 504]

  defp retryable_transport?(%Mint.TransportError{reason: reason}),
    do: retryable_transport?(reason)

  defp retryable_transport?(%Req.TransportError{reason: reason}), do: retryable_transport?(reason)

  defp retryable_transport?(reason),
    do: reason in [:closed, :timeout, :econnrefused, :await_status_timeout]

  defp retry_after_ms(headers) do
    Enum.find_value(headers, fn
      {name, value} when is_binary(name) ->
        if String.downcase(name) == "retry-after", do: parse_retry_after(value)

      _ ->
        nil
    end)
  end

  defp parse_retry_after(value) when is_binary(value) do
    case Integer.parse(value) do
      {seconds, _} when seconds >= 0 -> seconds * 1_000
      _ -> nil
    end
  end

  defp parse_retry_after(_), do: nil

  defp drain_error_response(ref, timeout), do: drain_error_response(ref, timeout, [], [])

  defp drain_error_response(ref, timeout, headers, acc) do
    receive do
      {^ref, {:headers, headers}} -> drain_error_response(ref, timeout, headers, acc)
      {^ref, {:data, chunk}} -> drain_error_response(ref, timeout, headers, [chunk | acc])
      {^ref, :done} -> {finalize_body(acc), headers}
      {^ref, {:error, _}} -> {finalize_body(acc), headers}
    after
      timeout -> {finalize_body(acc), headers}
    end
  end

  defp finalize_body(acc), do: acc |> Enum.reverse() |> IO.iodata_to_binary()

  defp stream_error_chunk(message) do
    data = Jason.encode!(%{"type" => "error", "message" => message})
    "data: " <> data <> "\n\n"
  end
end
