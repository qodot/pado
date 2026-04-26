defmodule Pado.LLMRouter.Message do
  @moduledoc """
  LLM 대화에 등장하는 메시지의 공통 정의.

  실제 메시지는 다음 셋 중 하나의 구조체다.

    * `Pado.LLMRouter.Message.User` — 사용자가 보낸 메시지
    * `Pado.LLMRouter.Message.Assistant` — 모델이 만든 응답
    * `Pado.LLMRouter.Message.ToolResult` — 도구 실행 결과

  Elixir의 태그된 유니언 패턴을 따른다. 호출자는 `role/1` 또는 구조체
  패턴 매칭으로 분기한다.

  ## 콘텐츠 블록

  Assistant 응답과 ToolResult는 여러 종류의 콘텐츠를 섞어 담을 수 있으므로
  `content_part/0` 태그된 튜플의 리스트로 표현한다. User 메시지는 단순
  문자열도 허용한다(프로바이더 어댑터가 변환 시점에 단일 텍스트 블록으로
  승격한다).
  """

  alias Pado.LLMRouter.Message.{Assistant, ToolResult, User}

  @typedoc "`role/1`의 반환값."
  @type role :: :user | :assistant | :tool_result

  @typedoc "세 종류의 메시지 중 어느 하나."
  @type t :: User.t() | Assistant.t() | ToolResult.t()

  @typedoc """
  콘텐츠 블록 하나. 어셈블된 Assistant 응답이나 도구 결과는 이 블록들의
  리스트로 표현된다.

    * `{:text, text}` — 일반 텍스트
    * `{:thinking, text}` — 모델의 내부 추론(표시하지 않는 프로바이더 있음)
    * `{:image, %{media_type, data}}` — base64로 인코딩된 이미지
    * `{:tool_call, %{id, name, args}}` — 모델이 호출을 요청한 도구 기술
  """
  @type content_part ::
          {:text, String.t()}
          | {:thinking, String.t()}
          | {:image, image_data}
          | {:tool_call, tool_call}

  @type image_data :: %{media_type: String.t(), data: binary}

  @type tool_call :: %{
          id: String.t(),
          name: String.t(),
          args: map
        }

  @doc """
  메시지의 role을 반환한다. 패턴 매칭이 쉬운 값(원자)로 돌려준다.
  """
  @spec role(t) :: role
  def role(%User{}), do: :user
  def role(%Assistant{}), do: :assistant
  def role(%ToolResult{}), do: :tool_result

  @doc """
  메시지의 텍스트 내용만을 이어붙여 돌려준다. 이미지/도구 호출 블록은
  건너뛴다. UI 미리보기, 로깅 등에 쓴다.
  """
  @spec text(t) :: String.t()
  def text(%User{content: content}) when is_binary(content), do: content
  def text(%User{content: parts}), do: join_text(parts)
  def text(%Assistant{content: parts}), do: join_text(parts)
  def text(%ToolResult{content: parts}), do: join_text(parts)

  defp join_text(parts) when is_list(parts) do
    parts
    |> Enum.flat_map(fn
      {:text, t} -> [t]
      _ -> []
    end)
    |> Enum.join()
  end
end
