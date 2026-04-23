defmodule Pado.LLMRouter.Message.Assistant do
  @moduledoc """
  모델이 돌려준 응답 메시지.

  스트리밍이 진행되는 동안은 `:content`가 부분적으로 채워진 상태일 수 있고,
  스트림이 종료(`Pado.LLMRouter.Event.Done` 또는 `Error`)될 때 비로소
  최종 모양이 확정된다.

  ## 필드

    * `:content` — 콘텐츠 블록 리스트. 텍스트, thinking, tool_call 등이
      모델의 응답 순서대로 들어 있다.
    * `:stop_reason` — 프로바이더가 보낸 정지 사유를 정규화한 값.
      `:stop | :length | :tool_use | :aborted | :error | nil`.
    * `:error_message` — `stop_reason`이 `:error` / `:aborted`일 때만 채워짐.
    * `:usage` — 이 응답을 만드는 데 든 토큰/비용. 스트림 종료 시점에 확정.
    * `:provider`, `:model`, `:api` — 실제로 응답을 만든 프로바이더/모델
      식별값. 다중 프로바이더 기록·감사용.
    * `:timestamp` — 응답 수신 시각.
  """

  alias Pado.LLMRouter.{Message, Model, Usage}

  @type stop_reason :: :stop | :length | :tool_use | :aborted | :error | nil

  @type t :: %__MODULE__{
          content: [Message.content_part()],
          stop_reason: stop_reason,
          error_message: String.t() | nil,
          usage: Usage.t() | nil,
          provider: Model.provider() | nil,
          model: String.t() | nil,
          api: Model.api() | nil,
          timestamp: DateTime.t() | nil
        }

  defstruct content: [],
            stop_reason: nil,
            error_message: nil,
            usage: nil,
            provider: nil,
            model: nil,
            api: nil,
            timestamp: nil

  @doc """
  `Model`에 기반해 초기화된 빈 Assistant 메시지를 돌려준다. 프로바이더
  어댑터가 스트림 시작 시점에 호출한다.
  """
  @spec init(Model.t()) :: t
  def init(%Model{} = m) do
    %__MODULE__{
      provider: m.provider,
      model: m.id,
      api: m.api,
      timestamp: DateTime.utc_now(),
      usage: Usage.empty()
    }
  end
end
