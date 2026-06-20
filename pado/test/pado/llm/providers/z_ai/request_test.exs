defmodule Pado.LLM.Providers.ZAI.RequestTest do
  use ExUnit.Case, async: true

  alias Pado.LLM.Message.{Assistant, ToolResult, User}
  alias Pado.LLM.Providers.ZAI.Request
  alias Pado.LLM.{Context, Model, Tool}

  @model %Model{
    id: "glm-test",
    provider: :z_ai,
    base_url: "https://api.z.ai/api/paas/v4/"
  }

  test "endpoint_url/1은 base_url 뒤에 Chat Completions 경로를 붙인다" do
    assert Request.endpoint_url(@model) == "https://api.z.ai/api/paas/v4/chat/completions"
  end

  test "build_body/4는 메시지와 도구를 OpenAI Chat Completions 포맷으로 변환한다" do
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
      Request.build_body(@model, ctx, "session-1",
        reasoning_effort: :xhigh,
        temperature: 0.2,
        tool_choice: "auto",
        tool_stream: true
      )

    assert body["model"] == "glm-test"
    assert body["stream"] == true
    assert body["temperature"] == 0.2
    assert body["tool_choice"] == "auto"
    assert body["tool_stream"] == true
    assert body["reasoning_effort"] == "max"

    assert body["messages"] == [
             %{"role" => "system", "content" => "한국어로 답한다."},
             %{
               "role" => "user",
               "content" => [
                 %{"type" => "text", "text" => "이 이미지를 설명해줘"},
                 %{
                   "type" => "image_url",
                   "image_url" => %{"url" => "data:image/png;base64,base64_dummy"}
                 }
               ]
             }
           ]

    assert body["tools"] == [
             %{
               "type" => "function",
               "function" => %{
                 "name" => "read_file",
                 "description" => "파일을 읽는다.",
                 "parameters" => tool.parameters
               }
             }
           ]
  end

  test "build_body/4는 assistant 도구 호출과 도구 결과를 이어지는 messages로 변환한다" do
    assistant = %Assistant{
      content: [
        {:text, "파일을 읽겠습니다."},
        {:tool_call, %{id: "call_1", name: "read_file", args: %{"path" => "README.md"}}}
      ]
    }

    result = ToolResult.text("call_1", "read_file", "# Pado")
    ctx = Context.new(messages: [assistant, result])

    messages = Request.build_body(@model, ctx, "session-1")["messages"]

    assert [assistant_message, tool_message] = messages
    assert assistant_message["role"] == "assistant"
    assert assistant_message["content"] == "파일을 읽겠습니다."

    assert [
             %{
               "id" => "call_1",
               "type" => "function",
               "function" => %{"name" => "read_file", "arguments" => arguments}
             }
           ] = assistant_message["tool_calls"]

    assert Jason.decode!(arguments) == %{"path" => "README.md"}
    assert tool_message == %{"role" => "tool", "tool_call_id" => "call_1", "content" => "# Pado"}
  end

  test "build_headers/3은 Z.AI SSE 호출에 필요한 헤더를 만든다" do
    headers = Request.build_headers("zai_dummy", "session-1")

    assert {"authorization", "Bearer zai_dummy"} in headers
    assert {"accept", "text/event-stream"} in headers
    assert {"content-type", "application/json"} in headers
    assert {"x-client-request-id", "session-1"} in headers

    assert Enum.any?(headers, fn {key, value} ->
             key == "user-agent" and String.starts_with?(value, "pado ")
           end)
  end

  test "build_body/4는 agent reasoning_effort를 Z.AI effective 값으로 변환한다" do
    assert reasoning_effort(:none) == "none"
    assert reasoning_effort(:low) == "high"
    assert reasoning_effort(:medium) == "high"
    assert reasoning_effort(:high) == "high"
    assert reasoning_effort(:xhigh) == "max"
  end

  defp reasoning_effort(value) do
    @model
    |> Request.build_body(Context.new(), "session-1", reasoning_effort: value)
    |> Map.fetch!("reasoning_effort")
  end
end
