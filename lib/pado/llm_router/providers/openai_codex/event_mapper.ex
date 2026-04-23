defmodule Pado.LLMRouter.Providers.OpenAICodex.EventMapper do
  @moduledoc """
  Codex `/codex/responses` SSE 이벤트를 `Pado.LLMRouter.Event` 유니언으로
  정규화한다.

  입력은 `Pado.LLMRouter.Providers.OpenAICodex.SSE.Event` 의 Enumerable 이고
  (각 `data` 필드는 Codex JSON 이벤트 한 개), 출력은 우리 Event 튜플의
  Enumerable 이다.

  ## 처리하는 Codex 이벤트

      response.created                          → {:start, ...}
      response.output_item.added (message)      → {:text_start, ...}
      response.output_item.added (function_call)→ {:tool_call_start, ...}
      response.output_text.delta                → {:text_delta, ...}
      response.output_text.done                 → {:text_end, ...}
      response.function_call_arguments.delta    → {:tool_call_delta, ...}
      response.function_call_arguments.done     → {:tool_call_end, ...}
      response.completed                        → {:done, ...}
      response.failed / error                   → {:error, ...}

  `response.in_progress` / `response.content_part.added` / `content_part.done` /
  `output_item.done` 등은 의미 있는 정보를 더 주지 않으므로 버린다.
  Reasoning 이벤트(`response.reasoning_*`)는 후속 커밋에서 지원한다.

  ## 누적 상태

  이 매퍼는 `Stream.transform/3` 안에서 가변 accumulator 역할을 하는 맵을
  유지한다:

    * `:assistant` — 지금까지 누적된 `Assistant` 메시지(최종 `{:done, _}`
      시점에 완성된다).
    * `:partial_text` — 아직 `text_done`이 오지 않은 현재 텍스트 블록 조각.
    * `:partial_args` — 스트리밍 중인 tool_call 의 JSON args 조각.
    * `:current_item` — 현재 진행 중인 output item (`message` or `function_call`).
    * `:model` — usage/cost 계산용.
  """

  alias Pado.LLMRouter.Message.Assistant
  alias Pado.LLMRouter.Providers.OpenAICodex.SSE
  alias Pado.LLMRouter.{Model, Usage}

  @doc """
  Enumerable of `SSE.Event` → Enumerable of `Pado.LLMRouter.Event` 튜플.
  """
  @spec map_stream(Enumerable.t(), Model.t()) :: Enumerable.t()
  def map_stream(sse_events, %Model{} = model) do
    Stream.transform(sse_events, init_state(model), &step/2)
  end

  # --- 상태 ---

  defp init_state(%Model{} = model) do
    %{
      model: model,
      assistant: Assistant.init(model),
      current_item: nil,
      partial_text: "",
      partial_args: ""
    }
  end

  # --- SSE 이벤트 → Codex JSON 디코드 ---

  defp step(%SSE.Event{data: ""}, state), do: {[], state}

  defp step(%SSE.Event{data: data}, state) do
    case Jason.decode(data) do
      {:ok, codex_event} -> handle(codex_event, state)
      {:error, _} -> {[], state}
    end
  end

  # --- Codex 이벤트 핸들러 ---

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
    {[{:text_start, %{index: idx}}], %{state | current_item: {:message, idx}, partial_text: ""}}
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
     %{state | current_item: {:function_call, idx, call_id, name}, partial_args: ""}}
  end

  defp handle(
         %{"type" => "response.output_text.delta", "output_index" => idx, "delta" => delta},
         state
       ) do
    {[{:text_delta, %{index: idx, delta: delta}}],
     %{state | partial_text: state.partial_text <> delta}}
  end

  defp handle(
         %{"type" => "response.output_text.done", "output_index" => idx, "text" => text},
         state
       ) do
    content = state.assistant.content ++ [{:text, text}]

    {[{:text_end, %{index: idx}}],
     %{state | assistant: %{state.assistant | content: content}, partial_text: ""}}
  end

  defp handle(
         %{
           "type" => "response.function_call_arguments.delta",
           "output_index" => idx,
           "delta" => delta
         },
         state
       ) do
    {[{:tool_call_delta, %{index: idx, delta: delta}}],
     %{state | partial_args: state.partial_args <> delta}}
  end

  defp handle(
         %{"type" => "response.function_call_arguments.done", "output_index" => idx},
         state
       ) do
    args =
      case Jason.decode(state.partial_args) do
        {:ok, m} when is_map(m) -> m
        _ -> %{}
      end

    assistant =
      case state.current_item do
        {:function_call, ^idx, call_id, name} ->
          block = {:tool_call, %{id: call_id, name: name, args: args}}
          %{state.assistant | content: state.assistant.content ++ [block]}

        _ ->
          state.assistant
      end

    {[{:tool_call_end, %{index: idx}}],
     %{state | assistant: assistant, partial_args: "", current_item: nil}}
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

  # 무시하는 이벤트 (in_progress, content_part.*, output_item.done 등)
  defp handle(_, state), do: {[], state}

  # --- usage / stop reason ---

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
