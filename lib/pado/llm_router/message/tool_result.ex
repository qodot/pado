defmodule Pado.LLMRouter.Message.ToolResult do
  @moduledoc """
  도구 실행 결과 메시지.

  `Pado.LLMRouter.Message.Assistant`의 응답에 포함된 `{:tool_call, _}`
  블록 하나에 대응하는 결과다. 같은 assistant 응답에 여러 도구 호출이
  있다면 ToolResult도 여러 개 생성된다.

  ## 필드

    * `:tool_call_id` — 대응되는 `tool_call`의 id. 프로바이더가 응답
      컨텍스트에서 이 필드로 매칭한다.
    * `:tool_name` — 실행된 도구 이름(로깅·관측용).
    * `:content` — 콘텐츠 블록 리스트. 보통 `{:text, _}` 하나지만 이미지를
      돌려주는 도구도 있다.
    * `:is_error` — 실행 중 에러가 발생해 결과가 오류 내용인 경우 `true`.
      모델에게 이 호출이 실패했음을 명시적으로 알린다.
    * `:timestamp` — 도구 실행이 끝난 시각.
  """

  alias Pado.LLMRouter.Message

  @type t :: %__MODULE__{
          tool_call_id: String.t(),
          tool_name: String.t(),
          content: [Message.content_part()],
          is_error: boolean,
          timestamp: DateTime.t() | nil
        }

  @enforce_keys [:tool_call_id, :tool_name]
  defstruct [
    :tool_call_id,
    :tool_name,
    content: [],
    is_error: false,
    timestamp: nil
  ]

  @doc "텍스트 내용으로 도구 결과를 만든다."
  @spec text(String.t(), String.t(), String.t(), keyword) :: t
  def text(tool_call_id, tool_name, text, opts \\ []) when is_binary(text) do
    %__MODULE__{
      tool_call_id: tool_call_id,
      tool_name: tool_name,
      content: [{:text, text}],
      is_error: Keyword.get(opts, :is_error, false),
      timestamp: DateTime.utc_now()
    }
  end

  @doc "에러 내용으로 도구 결과를 만든다. `is_error: true`가 설정된다."
  @spec error(String.t(), String.t(), String.t()) :: t
  def error(tool_call_id, tool_name, message) when is_binary(message) do
    text(tool_call_id, tool_name, message, is_error: true)
  end
end
