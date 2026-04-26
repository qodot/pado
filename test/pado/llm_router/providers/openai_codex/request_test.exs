defmodule Pado.LLMRouter.Providers.OpenAICodex.RequestTest do
  use ExUnit.Case, async: true

  alias Pado.LLMRouter.{Context, Model, Tool}
  alias Pado.LLMRouter.Message.{Assistant, ToolResult, User}
  alias Pado.LLMRouter.Providers.OpenAICodex.Request

  @model %Model{
    id: "gpt-test",
    provider: :openai_codex,
    base_url: "https://chatgpt.example/backend-api/"
  }

  test "endpoint_url/1은 base_url 뒤에 Codex responses 경로를 붙인다" do
    assert Request.endpoint_url(@model) == "https://chatgpt.example/backend-api/codex/responses"
  end

  test "build_body/3는 사용자 메시지와 도구, reasoning 옵션을 Codex 포맷으로 변환한다" do
    tool =
      Tool.new("read_file", "파일을 읽는다.", %{
        "type" => "object",
        "properties" => %{"path" => %{"type" => "string"}},
        "required" => ["path"]
      })

    ctx =
      Context.new(
        system_prompt: "한국어로 답한다.",
        messages: [
          User.new([
            {:text, "이 이미지를 설명해줘"},
            {:image, %{media_type: "image/png", data: "base64_dummy"}}
          ])
        ],
        tools: [tool]
      )

    body =
      Request.build_body(@model, ctx,
        session_id: "session-1",
        reasoning_effort: :low,
        temperature: 0.2
      )

    assert body["model"] == "gpt-test"
    assert body["store"] == false
    assert body["stream"] == true
    assert body["instructions"] == "한국어로 답한다."
    assert body["prompt_cache_key"] == "session-1"
    assert body["temperature"] == 0.2
    assert body["reasoning"] == %{"effort" => "low", "summary" => "auto"}

    assert body["input"] == [
             %{
               "role" => "user",
               "content" => [
                 %{"type" => "input_text", "text" => "이 이미지를 설명해줘"},
                 %{
                   "type" => "input_image",
                   "detail" => "auto",
                   "image_url" => "data:image/png;base64,base64_dummy"
                 }
               ]
             }
           ]

    assert body["tools"] == [
             %{
               "type" => "function",
               "name" => "read_file",
               "description" => "파일을 읽는다.",
               "parameters" => tool.parameters
             }
           ]
  end

  test "build_body/3는 assistant 도구 호출과 도구 결과를 이어지는 input으로 변환한다" do
    assistant = %Assistant{
      content: [
        {:text, "파일을 읽겠습니다."},
        {:tool_call, %{id: "call_1", name: "read_file", args: %{"path" => "README.md"}}}
      ]
    }

    result = ToolResult.text("call_1", "read_file", "# Pado")
    ctx = Context.new(messages: [assistant, result])

    input = Request.build_body(@model, ctx, session_id: "session-1")["input"]

    assert [message, function_call, function_output] = input

    assert message == %{
             "type" => "message",
             "role" => "assistant",
             "content" => [
               %{"type" => "output_text", "text" => "파일을 읽겠습니다.", "annotations" => []}
             ],
             "status" => "completed"
           }

    assert function_call["type"] == "function_call"
    assert function_call["call_id"] == "call_1"
    assert function_call["name"] == "read_file"
    assert Jason.decode!(function_call["arguments"]) == %{"path" => "README.md"}

    assert function_output == %{
             "type" => "function_call_output",
             "call_id" => "call_1",
             "output" => "# Pado"
           }
  end

  test "build_headers/3는 Codex SSE 호출에 필요한 헤더를 만든다" do
    headers =
      Request.build_headers("access_dummy", "acct_dummy",
        session_id: "session-1",
        originator: "pi"
      )

    assert {"authorization", "Bearer access_dummy"} in headers
    assert {"chatgpt-account-id", "acct_dummy"} in headers
    assert {"originator", "pi"} in headers
    assert {"openai-beta", "responses=experimental"} in headers
    assert {"accept", "text/event-stream"} in headers
    assert {"content-type", "application/json"} in headers
    assert {"session_id", "session-1"} in headers
    assert {"x-client-request-id", "session-1"} in headers

    assert Enum.any?(headers, fn {key, value} ->
             key == "user-agent" and String.starts_with?(value, "pado ")
           end)
  end

  test "ensure_session_id/1는 헤더와 바디가 같은 session_id를 쓰게 한다" do
    opts = Request.ensure_session_id([])
    session_id = Keyword.fetch!(opts, :session_id)

    headers = Request.build_headers("access_dummy", "acct_dummy", opts)
    body = Request.build_body(@model, Context.new(), opts)

    assert {"session_id", session_id} in headers
    assert {"x-client-request-id", session_id} in headers
    assert body["prompt_cache_key"] == session_id
  end
end
