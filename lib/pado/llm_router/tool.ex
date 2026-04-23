defmodule Pado.LLMRouter.Tool do
  @moduledoc """
  LLM이 호출할 수 있는 도구(함수) 기술.

  이 구조체는 **어떤 도구가 있고 파라미터 스키마가 무엇인지**만 담는다.
  실제 실행 로직은 상위 계층(`Pado.Agent`)의 책임이다. 즉 `Pado.LLMRouter`는
  "LLM에게 도구 목록을 알려주고, 모델이 요청한 호출을 메시지로 돌려주기"까지만
  하고, 도구 실행은 하지 않는다.

  ## 필드

    * `:name` — 도구 이름. LLM이 이 이름으로 호출을 요청한다.
    * `:description` — LLM이 언제 호출할지 판단할 때 참고하는 설명.
    * `:parameters` — JSON Schema(object 루트). Pi의 `typebox` 스키마,
      req_llm의 `ReqLLM.Tool`의 `parameter_schema`와 같은 역할.
      예: `%{"type" => "object", "properties" => %{…}, "required" => […]}`
    * `:metadata` — 프로바이더/호출자가 임의로 덧붙이는 값. 호출 결과를
      매칭·라우팅할 때 쓸 수 있다.

  ## 예

      %Pado.LLMRouter.Tool{
        name: "read_file",
        description: "파일을 읽어 텍스트 내용을 반환한다.",
        parameters: %{
          "type" => "object",
          "properties" => %{
            "path" => %{"type" => "string", "description" => "읽을 파일 경로"}
          },
          "required" => ["path"]
        }
      }
  """

  @type json_schema :: map

  @type t :: %__MODULE__{
          name: String.t(),
          description: String.t(),
          parameters: json_schema,
          metadata: map
        }

  @enforce_keys [:name, :description, :parameters]
  defstruct [:name, :description, :parameters, metadata: %{}]

  @doc """
  빠른 생성자. 필수 필드만 받고 나머지는 기본값.

      Tool.new("get_weather", "도시의 현재 날씨를 조회한다.",
        %{"type" => "object",
          "properties" => %{"city" => %{"type" => "string"}},
          "required" => ["city"]})
  """
  @spec new(String.t(), String.t(), json_schema, keyword) :: t
  def new(name, description, parameters, opts \\ []) do
    %__MODULE__{
      name: name,
      description: description,
      parameters: parameters,
      metadata: Keyword.get(opts, :metadata, %{})
    }
  end
end
