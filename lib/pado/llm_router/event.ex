defmodule Pado.LLMRouter.Event do
  @moduledoc """
  LLM 스트리밍 응답 이벤트의 정규화된 유니언 타입.

  프로바이더(OpenAI Codex SSE, Anthropic messages stream, Gemini 등)마다
  이벤트 모양이 다르지만, Pado는 아래 태그된 튜플 하나의 리스트로
  정규화해 상위 계층에 노출한다.

  ## 수명 주기

  정상 스트림은 다음 순서를 따른다:

      {:start, %{message: initial_assistant}}
      (
        {:text_start,    %{index: i}}
        {:text_delta,    %{index: i, delta: "토큰"}}  *
        {:text_end,      %{index: i}}
        | {:thinking_start, ...} / _delta / _end
        | {:tool_call_start, %{index, id, name}}
          {:tool_call_delta, %{index, delta: "json조각"}} *
          {:tool_call_end,   %{index}}
      ) *
      {:done, %{stop_reason, message: final_assistant}}

  오류 시에는 언제든 `:error`로 스트림이 종료된다:

      {:error, %{reason, message: final_assistant, error_message}}

  ## 왜 구조체가 아니라 태그된 튜플인가

  Elixir 관용구. `case` / `receive` 패턴 매칭이 자연스럽고, 생성 비용이
  낮으며, 새 이벤트 종류 추가가 단순하다. 상위 계층이 필요하면 이 튜플을
  자기 구조체로 감싸면 된다.

  ## Pi와의 차이

  Pi의 `AssistantMessageEvent`와 거의 1:1이지만, Pi는 `contentIndex`를
  전역 콘텐츠 배열의 인덱스로 쓰는 반면 Pado는 `:index`로 축약한다.
  """

  alias Pado.LLMRouter.{Message, Usage}

  @type stop_reason :: Message.Assistant.stop_reason()

  @typedoc "스트림 이벤트 유니언."
  @type t ::
          {:start, start_payload}
          | {:text_start, index_payload}
          | {:text_delta, delta_payload}
          | {:text_end, index_payload}
          | {:thinking_start, index_payload}
          | {:thinking_delta, delta_payload}
          | {:thinking_end, index_payload}
          | {:tool_call_start, tool_call_start_payload}
          | {:tool_call_delta, delta_payload}
          | {:tool_call_end, index_payload}
          | {:done, done_payload}
          | {:error, error_payload}

  @type start_payload :: %{message: Message.Assistant.t()}

  @type index_payload :: %{index: non_neg_integer}

  @type delta_payload :: %{
          index: non_neg_integer,
          delta: String.t()
        }

  @type tool_call_start_payload :: %{
          index: non_neg_integer,
          id: String.t(),
          name: String.t()
        }

  @type done_payload :: %{
          stop_reason: stop_reason,
          usage: Usage.t(),
          message: Message.Assistant.t()
        }

  @type error_payload :: %{
          reason: :error | :aborted,
          error_message: String.t(),
          message: Message.Assistant.t(),
          usage: Usage.t()
        }

  @doc """
  스트림 종료 이벤트(`:done` 또는 `:error`)인지 확인한다. 스트림 소비자가
  루프 탈출 조건에 쓴다.
  """
  @spec terminal?(t) :: boolean
  def terminal?({:done, _}), do: true
  def terminal?({:error, _}), do: true
  def terminal?(_), do: false

  @doc """
  종료 이벤트에서 최종 assistant 메시지를 꺼낸다. 종료 이벤트가 아니면 `nil`.
  """
  @spec final_message(t) :: Message.Assistant.t() | nil
  def final_message({:done, %{message: m}}), do: m
  def final_message({:error, %{message: m}}), do: m
  def final_message(_), do: nil
end
