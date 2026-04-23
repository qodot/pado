defmodule Pado.LLMRouter.Context do
  @moduledoc """
  LLM 한 번의 호출에 보내는 입력 묶음.

  `system_prompt` + 대화 `messages` + 선택적인 `tools` 목록이 한 Context를
  이룬다. 프로바이더 어댑터는 이 구조체를 받아 프로바이더 고유 포맷으로
  변환해 송신한다.

  Context는 **불변 값 객체**다. 대화가 진행되며 메시지가 누적될 때마다
  `append/2`로 새 Context를 만든다.

  ## 필드

    * `:system_prompt` — 선택. 시스템 역할 프롬프트.
    * `:messages` — 순서 있는 대화 메시지 리스트. User/Assistant/ToolResult
      섞여 있을 수 있다.
    * `:tools` — 선택. 이번 호출에서 노출할 도구 목록. `nil`이면 도구 호출
      비활성.

  ## 예

      ctx =
        Context.new(system_prompt: "You are helpful.")
        |> Context.append(Message.User.new("2 + 2?"))
  """

  alias Pado.LLMRouter.{Message, Tool}

  @type t :: %__MODULE__{
          system_prompt: String.t() | nil,
          messages: [Message.t()],
          tools: [Tool.t()] | nil
        }

  defstruct system_prompt: nil, messages: [], tools: nil

  @doc """
  새 Context를 만든다.

  옵션:

    * `:system_prompt` — 시스템 프롬프트.
    * `:messages` — 초기 메시지 리스트 (기본 `[]`).
    * `:tools` — 초기 도구 목록 (기본 `nil`).
  """
  @spec new(keyword) :: t
  def new(opts \\ []) do
    %__MODULE__{
      system_prompt: Keyword.get(opts, :system_prompt),
      messages: Keyword.get(opts, :messages, []),
      tools: Keyword.get(opts, :tools)
    }
  end

  @doc "메시지 하나를 컨텍스트 끝에 붙인 새 Context를 반환한다."
  @spec append(t, Message.t()) :: t
  def append(%__MODULE__{messages: msgs} = ctx, message) do
    %__MODULE__{ctx | messages: msgs ++ [message]}
  end

  @doc "여러 메시지를 한 번에 붙인다."
  @spec append_all(t, [Message.t()]) :: t
  def append_all(%__MODULE__{messages: msgs} = ctx, new_msgs) when is_list(new_msgs) do
    %__MODULE__{ctx | messages: msgs ++ new_msgs}
  end

  @doc "도구 목록을 교체한 새 Context를 반환한다."
  @spec put_tools(t, [Tool.t()] | nil) :: t
  def put_tools(%__MODULE__{} = ctx, tools), do: %__MODULE__{ctx | tools: tools}

  @doc "시스템 프롬프트를 교체한 새 Context를 반환한다."
  @spec put_system_prompt(t, String.t() | nil) :: t
  def put_system_prompt(%__MODULE__{} = ctx, prompt),
    do: %__MODULE__{ctx | system_prompt: prompt}

  @doc "메시지 수."
  @spec size(t) :: non_neg_integer
  def size(%__MODULE__{messages: m}), do: length(m)

  @doc "마지막 메시지 반환(없으면 `nil`)."
  @spec last_message(t) :: Message.t() | nil
  def last_message(%__MODULE__{messages: []}), do: nil
  def last_message(%__MODULE__{messages: m}), do: List.last(m)
end
