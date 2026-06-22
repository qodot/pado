defmodule Pado.LLM.Providers.ZAI.EventMapper do
  alias Pado.LLM.Message.Assistant
  alias Pado.LLM.{Model, SSE, Usage}

  def map_stream(sse_events, %Model{} = model) do
    Stream.transform(sse_events, init_state(model), &step/2)
  end

  defp init_state(%Model{} = model) do
    %{
      model: model,
      assistant: Assistant.init(model),
      started: false,
      done: false,
      text_started: false,
      partial_text: "",
      thinking_started: false,
      partial_thinking: "",
      stop_reason: nil,
      tool_calls: %{}
    }
  end

  defp step(%SSE.Event{data: ""}, state), do: {[], state}
  defp step(%SSE.Event{data: "[DONE]"}, %{done: true} = state), do: {[], state}
  defp step(%SSE.Event{data: "[DONE]"}, state), do: finish(state)

  defp step(%SSE.Event{data: data}, state) do
    case Jason.decode(data) do
      {:ok, %{"error" => error}} -> handle_error(error, state)
      {:ok, %{"type" => "error"} = error} -> handle_error(error, state)
      {:ok, chunk} -> handle_chunk(chunk, state)
      {:error, _} -> {[], state}
    end
  end

  defp handle_chunk(%{"choices" => choices} = chunk, state) when is_list(choices) do
    usage = Map.get(chunk, "usage")
    state = if is_map(usage), do: put_usage(state, usage), else: state

    Enum.reduce(choices, {[], state}, fn choice, {events, state} ->
      {choice_events, state} = handle_choice(choice, state)
      {events ++ choice_events, state}
    end)
  end

  defp handle_chunk(_, state), do: {[], state}

  defp handle_choice(%{"delta" => delta} = choice, state) when is_map(delta) do
    {start_events, state} = ensure_started(state)
    {events, state} = handle_delta(delta, state)
    state = record_finish_reason(Map.get(choice, "finish_reason"), state)

    {start_events ++ events, state}
  end

  defp handle_choice(%{"finish_reason" => finish_reason}, state) when not is_nil(finish_reason) do
    {start_events, state} = ensure_started(state)
    {start_events, record_finish_reason(finish_reason, state)}
  end

  defp handle_choice(_, state), do: {[], state}

  defp handle_delta(delta, state) do
    {thinking_events, state} = handle_reasoning_delta(Map.get(delta, "reasoning_content"), state)
    {text_events, state} = handle_content_delta(Map.get(delta, "content"), state)
    {tool_events, state} = handle_tool_calls_delta(Map.get(delta, "tool_calls"), state)
    {thinking_events ++ text_events ++ tool_events, state}
  end

  defp handle_reasoning_delta(content, state) when is_binary(content) and content != "" do
    events =
      if state.thinking_started do
        [{:thinking_delta, %{index: 0, delta: content}}]
      else
        [{:thinking_start, %{index: 0}}, {:thinking_delta, %{index: 0, delta: content}}]
      end

    {events,
     %{state | thinking_started: true, partial_thinking: state.partial_thinking <> content}}
  end

  defp handle_reasoning_delta(_, state), do: {[], state}

  defp handle_content_delta(content, state) when is_binary(content) and content != "" do
    {thinking_events, state} = close_thinking(state)

    events =
      if state.text_started do
        [{:text_delta, %{index: 0, delta: content}}]
      else
        [{:text_start, %{index: 0}}, {:text_delta, %{index: 0, delta: content}}]
      end

    {thinking_events ++ events,
     %{state | text_started: true, partial_text: state.partial_text <> content}}
  end

  defp handle_content_delta(_, state), do: {[], state}

  defp handle_tool_calls_delta(tool_calls, state) when is_list(tool_calls) do
    Enum.reduce(tool_calls, {[], state}, fn tool_call, {events, state} ->
      {tool_events, state} = handle_tool_call_delta(tool_call, state)
      {events ++ tool_events, state}
    end)
  end

  defp handle_tool_calls_delta(_, state), do: {[], state}

  defp handle_tool_call_delta(%{"index" => index} = tool_call, state) do
    function = Map.get(tool_call, "function", %{})

    current =
      Map.get(state.tool_calls, index, %{
        id: Map.get(tool_call, "id", ""),
        name: Map.get(function, "name", ""),
        args: "",
        started: false
      })

    updated = %{
      current
      | id: Map.get(tool_call, "id") || current.id,
        name: Map.get(function, "name") || current.name,
        args: current.args <> (Map.get(function, "arguments") || "")
    }

    events =
      if current.started do
        []
      else
        [{:tool_call_start, %{index: index, id: updated.id, name: updated.name}}]
      end

    arg_delta = Map.get(function, "arguments")

    events =
      if is_binary(arg_delta) and arg_delta != "" do
        events ++ [{:tool_call_delta, %{index: index, delta: arg_delta}}]
      else
        events
      end

    {events, %{state | tool_calls: Map.put(state.tool_calls, index, %{updated | started: true})}}
  end

  defp handle_tool_call_delta(_, state), do: {[], state}

  defp ensure_started(%{started: true} = state), do: {[], state}

  defp ensure_started(state),
    do: {[{:start, %{message: state.assistant}}], %{state | started: true}}

  defp finish(state) do
    {start_events, state} = ensure_started(state)
    {finish_events, state} = finish_open_items(state)
    stop = state.stop_reason || stop_reason(nil, state)
    usage = state.assistant.usage || Usage.empty()

    final_msg = %{
      state.assistant
      | content: build_content(state),
        stop_reason: stop,
        usage: usage
    }

    events =
      start_events ++
        finish_events ++ [{:done, %{stop_reason: stop, usage: usage, message: final_msg}}]

    {events, %{state | assistant: final_msg, done: true}}
  end

  defp finish_open_items(state) do
    {thinking_events, state} = close_thinking(state)
    text_events = if state.text_started, do: [{:text_end, %{index: 0}}], else: []

    tool_events =
      state.tool_calls
      |> Map.keys()
      |> Enum.sort()
      |> Enum.map(&{:tool_call_end, %{index: &1}})

    {thinking_events ++ text_events ++ tool_events, state}
  end

  defp build_content(state) do
    thinking =
      if state.partial_thinking == "" do
        []
      else
        [{:thinking, state.partial_thinking}]
      end

    text =
      if state.partial_text == "" do
        []
      else
        [{:text, state.partial_text}]
      end

    tool_calls =
      state.tool_calls
      |> Enum.sort_by(fn {index, _} -> index end)
      |> Enum.map(fn {_index, call} ->
        {:tool_call, %{id: call.id, name: call.name, args: decode_args(call.args)}}
      end)

    thinking ++ text ++ tool_calls
  end

  defp close_thinking(%{thinking_started: true} = state),
    do: {[{:thinking_end, %{index: 0}}], %{state | thinking_started: false}}

  defp close_thinking(state), do: {[], state}

  defp decode_args(args) do
    case Jason.decode(args) do
      {:ok, decoded} when is_map(decoded) -> decoded
      _ -> %{}
    end
  end

  defp put_usage(state, usage) do
    pado_usage = build_usage(usage, state.model)
    %{state | assistant: %{state.assistant | usage: pado_usage}}
  end

  defp build_usage(usage, %Model{} = model) do
    cached = get_in(usage, ["prompt_tokens_details", "cached_tokens"]) || 0
    input = (usage["prompt_tokens"] || 0) - cached
    output = usage["completion_tokens"] || 0
    total = usage["total_tokens"] || input + cached + output

    pado_usage = %Usage{
      input: input,
      output: output,
      cache_read: cached,
      cache_write: 0,
      total_tokens: total
    }

    %{pado_usage | cost: Model.calculate_cost(model, pado_usage)}
  end

  defp handle_error(error, state) do
    message =
      cond do
        is_binary(error) -> error
        is_map(error) -> Map.get(error, "message") || Map.get(error, "code") || "unknown error"
        true -> "unknown error"
      end

    final_msg = %{state.assistant | stop_reason: :error, error_message: message}

    {[
       {:error,
        %{
          reason: :error,
          error_message: message,
          message: final_msg,
          usage: state.assistant.usage || Usage.empty()
        }}
     ], state}
  end

  defp record_finish_reason(nil, state), do: state
  defp record_finish_reason(reason, state), do: %{state | stop_reason: stop_reason(reason, state)}

  defp stop_reason("length", _state), do: :length
  defp stop_reason("tool_calls", _state), do: :tool_use

  defp stop_reason(_reason, %{tool_calls: tool_calls}) when map_size(tool_calls) > 0,
    do: :tool_use

  defp stop_reason(_reason, _state), do: :stop
end
