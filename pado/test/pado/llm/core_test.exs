defmodule Pado.LLM.CoreTest do
  use ExUnit.Case, async: true

  alias Pado.LLM.{Context, Message, Model, Tool, Usage}
  alias Pado.LLM.Message.{Assistant, ToolResult, User}

  test "Context는 메시지와 도구를 불변 방식으로 누적한다" do
    user = User.new("안녕")
    assistant = %Assistant{content: [{:text, "반가워요"}]}
    tool = Tool.new("get_weather", "날씨를 조회한다.", %{"type" => "object"})

    ctx =
      Context.new(system_prompt: "친절하게 답한다.")
      |> Context.append(user)
      |> Context.append_all([assistant])
      |> Context.put_tools([tool])

    assert ctx.system_prompt == "친절하게 답한다."
    assert ctx.messages == [user, assistant]
    assert ctx.tools == [tool]
    assert Context.size(ctx) == 2
    assert Context.last_message(ctx) == assistant

    without_prompt = Context.put_system_prompt(ctx, nil)
    assert without_prompt.system_prompt == nil
    assert ctx.system_prompt == "친절하게 답한다."
  end

  test "Message.text/1은 텍스트 블록만 이어붙인다" do
    assert Message.role(User.new("질문")) == :user
    assert Message.text(User.new("질문")) == "질문"

    user =
      User.new([
        {:text, "이미지 설명: "},
        {:image, %{media_type: "image/png", data: "base64_dummy"}},
        {:text, "끝"}
      ])

    assistant = %Assistant{
      content: [
        {:thinking, "숨겨진 추론"},
        {:text, "안녕"},
        {:tool_call, %{id: "call_1", name: "noop", args: %{}}},
        {:text, "하세요"}
      ]
    }

    result = ToolResult.text("call_1", "noop", "도구 결과")

    assert Message.text(user) == "이미지 설명: 끝"
    assert Message.text(assistant) == "안녕하세요"
    assert Message.role(result) == :tool_result
    assert Message.text(result) == "도구 결과"
  end

  test "Tool.new/4는 도구 기술 구조체를 만든다" do
    schema = %{
      "type" => "object",
      "properties" => %{"city" => %{"type" => "string"}},
      "required" => ["city"]
    }

    tool = Tool.new("get_weather", "도시의 날씨를 조회한다.", schema, metadata: %{safe: true})

    assert tool.name == "get_weather"
    assert tool.description == "도시의 날씨를 조회한다."
    assert tool.parameters == schema
    assert tool.metadata == %{safe: true}
  end

  test "Usage.add/2는 토큰과 비용을 합산한다" do
    a = %Usage{
      input: 1,
      output: 2,
      cache_read: 3,
      cache_write: 4,
      total_tokens: 10,
      cost: %{input: 0.1, output: 0.2, cache_read: 0.3, cache_write: 0.4, total: 1.0}
    }

    b = %Usage{
      input: 10,
      output: 20,
      cache_read: 30,
      cache_write: 40,
      total_tokens: 100,
      cost: %{input: 1.0, output: 2.0, cache_read: 3.0, cache_write: 4.0, total: 10.0}
    }

    assert Usage.add(a, b) == %Usage{
             input: 11,
             output: 22,
             cache_read: 33,
             cache_write: 44,
             total_tokens: 110,
             cost: %{input: 1.1, output: 2.2, cache_read: 3.3, cache_write: 4.4, total: 11.0}
           }
  end

  test "Model.calculate_cost/2는 100만 토큰당 단가로 비용을 계산한다" do
    model = %Model{
      id: "dummy",
      provider: :dummy,
      cost: %{input: 2.0, output: 10.0, cache_read: 0.5, cache_write: 1.0}
    }

    usage = %Usage{input: 1_000_000, output: 500_000, cache_read: 2_000_000, cache_write: 250_000}

    assert Model.calculate_cost(model, usage) == %{
             input: 2.0,
             output: 5.0,
             cache_read: 1.0,
             cache_write: 0.25,
             total: 8.25
           }
  end
end
