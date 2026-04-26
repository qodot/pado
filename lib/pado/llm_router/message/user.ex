defmodule Pado.LLMRouter.Message.User do
  @moduledoc """
  사용자 입력 메시지.

  `:content`는 단순 문자열이거나 콘텐츠 블록 리스트다. 이미지를 포함하려면
  리스트 형태로 `{:text, _}`과 `{:image, _}`을 섞는다. 프로바이더 어댑터가
  호출 시점에 프로바이더 고유 포맷으로 변환한다.

  ## 예

      Pado.LLMRouter.Message.User.new("안녕")

      Pado.LLMRouter.Message.User.new([
        {:text, "이 사진을 설명해줘"},
        {:image, %{media_type: "image/png", data: binary}}
      ])
  """

  alias Pado.LLMRouter.Message

  @type t :: %__MODULE__{
          content: String.t() | [Message.content_part()],
          timestamp: DateTime.t() | nil
        }

  @enforce_keys [:content]
  defstruct [:content, timestamp: nil]

  @doc "문자열 또는 콘텐츠 블록 리스트로 새 User 메시지를 만든다."
  @spec new(String.t() | [Message.content_part()]) :: t
  def new(content) when is_binary(content) or is_list(content) do
    %__MODULE__{content: content, timestamp: DateTime.utc_now()}
  end
end
