defmodule Pado.LLM.Providers.OpenAICodex.EventMapper do
  alias Pado.LLM.Message.Assistant
  alias Pado.LLM.Providers.OpenAICodex.SSE
  alias Pado.LLM.{Model, Usage}

  @reasoning_delta_types [
    "response.reasoning.delta",
    "response.reasoning_text.delta",
    "response.reasoning_summary.delta",
    "response.reasoning_summary_text.delta"
  ]

  @reasoning_done_types [
    "response.reasoning.done",
    "response.reasoning_text.done",
    "response.reasoning_summary.done",
    "response.reasoning_summary_text.done"
  ]

  def map_stream(sse_events, %Model{} = model) do
    Stream.transform(sse_events, init_state(model), &step/2)
  end

  defp init_state(%Model{} = model) do
    %{
      model: model,
      assistant: Assistant.init(model),
      items: %{},
      partial_text: %{},
      partial_args: %{},
      partial_thinking: %{}
    }
  end

  defp step(%SSE.Event{data: ""}, state), do: {[], state}

  defp step(%SSE.Event{data: data}, state) do
    case Jason.decode(data) do
      {:ok, codex_event} -> handle(codex_event, state)
      {:error, _} -> {[], state}
    end
  end

  defp handle(%{"type" => "response.created"}, state) do
    {[{:start, %{message: state.assistant}}], state}
  end

  defp handle(
         %{
           "type" => "response.output_item.added",
           "output_index" => idx,
           "item" => %{"type" => "message"}
         },
         state
       ) do
    {[{:text_start, %{index: idx}}],
     %{
       state
       | items: Map.put(state.items, idx, {:message, idx}),
         partial_text: Map.put(state.partial_text, idx, "")
     }}
  end

  defp handle(
         %{
           "type" => "response.output_item.added",
           "output_index" => idx,
           "item" => %{"type" => "function_call"} = item
         },
         state
       ) do
    call_id = Map.get(item, "call_id", "")
    name = Map.get(item, "name", "")

    {[{:tool_call_start, %{index: idx, id: call_id, name: name}}],
     %{
       state
       | items: Map.put(state.items, idx, {:function_call, idx, call_id, name}),
         partial_args: Map.put(state.partial_args, idx, "")
     }}
  end

  defp handle(
         %{
           "type" => "response.output_item.added",
           "output_index" => idx,
           "item" => %{"type" => "reasoning"}
         },
         state
       ) do
    {[{:thinking_start, %{index: idx}}],
     %{
       state
       | items: Map.put(state.items, idx, {:reasoning, idx}),
         partial_thinking: Map.put(state.partial_thinking, idx, "")
     }}
  end

  defp handle(
         %{"type" => "response.output_text.delta", "output_index" => idx, "delta" => delta},
         state
       ) do
    partial_text = append_partial(state.partial_text, idx, delta)

    {[{:text_delta, %{index: idx, delta: delta}}], %{state | partial_text: partial_text}}
  end

  defp handle(
         %{"type" => "response.output_text.done", "output_index" => idx, "text" => text},
         state
       ) do
    content = state.assistant.content ++ [{:text, text}]

    {[{:text_end, %{index: idx}}],
     %{
       state
       | assistant: %{state.assistant | content: content},
         partial_text: Map.delete(state.partial_text, idx),
         items: Map.delete(state.items, idx)
     }}
  end

  defp handle(
         %{
           "type" => "response.function_call_arguments.delta",
           "output_index" => idx,
           "delta" => delta
         },
         state
       ) do
    partial_args = append_partial(state.partial_args, idx, delta)

    {[{:tool_call_delta, %{index: idx, delta: delta}}], %{state | partial_args: partial_args}}
  end

  defp handle(
         %{"type" => "response.function_call_arguments.done", "output_index" => idx},
         state
       ) do
    args_text = Map.get(state.partial_args, idx, "")

    args =
      case Jason.decode(args_text) do
        {:ok, m} when is_map(m) -> m
        _ -> %{}
      end

    assistant =
      case Map.get(state.items, idx) do
        {:function_call, ^idx, call_id, name} ->
          block = {:tool_call, %{id: call_id, name: name, args: args}}
          %{state.assistant | content: state.assistant.content ++ [block]}

        _ ->
          state.assistant
      end

    {[{:tool_call_end, %{index: idx}}],
     %{
       state
       | assistant: assistant,
         partial_args: Map.delete(state.partial_args, idx),
         items: Map.delete(state.items, idx)
     }}
  end

  defp handle(%{"type" => type, "delta" => delta} = ev, state)
       when type in @reasoning_delta_types do
    idx = Map.get(ev, "output_index") || 0

    partial_thinking = append_partial(state.partial_thinking, idx, delta)

    {[{:thinking_delta, %{index: idx, delta: delta}}],
     %{state | partial_thinking: partial_thinking}}
  end

  defp handle(%{"type" => type} = ev, state) when type in @reasoning_done_types do
    idx = Map.get(ev, "output_index") || 0

    text =
      case Map.get(ev, "text") do
        text when is_binary(text) and text != "" -> text
        _ -> Map.get(state.partial_thinking, idx, "")
      end

    assistant =
      if text == "" do
        state.assistant
      else
        %{state.assistant | content: state.assistant.content ++ [{:thinking, text}]}
      end

    {[{:thinking_end, %{index: idx}}],
     %{
       state
       | assistant: assistant,
         partial_thinking: Map.delete(state.partial_thinking, idx),
         items: Map.delete(state.items, idx)
     }}
  end

  defp handle(%{"type" => "response.completed", "response" => response}, state) do
    usage = build_usage(response, state.model)
    stop = determine_stop_reason(state.assistant, response)

    final_msg = %{state.assistant | stop_reason: stop, usage: usage}

    {[{:done, %{stop_reason: stop, usage: usage, message: final_msg}}],
     %{state | assistant: final_msg}}
  end

  defp handle(%{"type" => "response.failed", "response" => response}, state) do
    error_msg = get_in(response, ["error", "message"]) || "response failed"
    final_msg = %{state.assistant | stop_reason: :error, error_message: error_msg}

    {[
       {:error,
        %{
          reason: :error,
          error_message: error_msg,
          message: final_msg,
          usage: state.assistant.usage || Usage.empty()
        }}
     ], state}
  end

  defp handle(%{"type" => "error"} = ev, state) do
    error_msg = Map.get(ev, "message") || Map.get(ev, "code") || "unknown error"
    final_msg = %{state.assistant | stop_reason: :error, error_message: error_msg}

    {[
       {:error,
        %{
          reason: :error,
          error_message: error_msg,
          message: final_msg,
          usage: state.assistant.usage || Usage.empty()
        }}
     ], state}
  end

  defp handle(_, state), do: {[], state}

  defp append_partial(parts, idx, delta) do
    Map.update(parts, idx, delta, &(&1 <> delta))
  end

  defp build_usage(response, %Model{} = model) do
    u = response["usage"] || %{}
    cached = get_in(u, ["input_tokens_details", "cached_tokens"]) || 0
    input = (u["input_tokens"] || 0) - cached
    output = u["output_tokens"] || 0
    total = u["total_tokens"] || 0

    usage = %Usage{
      input: input,
      output: output,
      cache_read: cached,
      cache_write: 0,
      total_tokens: total
    }

    %{usage | cost: Model.calculate_cost(model, usage)}
  end

  defp determine_stop_reason(%Assistant{content: content}, response) do
    has_tool_call = Enum.any?(content, &match?({:tool_call, _}, &1))

    cond do
      has_tool_call -> :tool_use
      response["status"] == "completed" -> :stop
      response["status"] == "incomplete" -> :length
      response["status"] in ["failed", "cancelled"] -> :error
      true -> :stop
    end
  end
end
