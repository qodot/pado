defmodule Pado.Agent.TurnTest do
  use ExUnit.Case, async: true

  alias Pado.Agent.Turn
  alias Pado.LLMRouter.Message.{Assistant, ToolResult, User}

  describe "flatten/1" do
    test "injected, assistant, tool_results를 시간순으로 펼친다" do
      injected = [User.new("잠깐 X도 봐줘")]
      assistant = %Assistant{content: [{:text, "ok"}]}

      tool_results = [
        ToolResult.text("c1", "search", "결과 1"),
        ToolResult.text("c2", "fetch", "결과 2")
      ]

      turn = %Turn{
        index: 1,
        injected: injected,
        assistant: assistant,
        tool_results: tool_results
      }

      assert Turn.flatten(turn) == injected ++ [assistant] ++ tool_results
    end

    test "injected가 비어 있으면 assistant + tool_results만" do
      assistant = %Assistant{content: [{:text, "hi"}]}
      tr = ToolResult.text("c1", "t", "r")

      turn = %Turn{
        index: 1,
        injected: [],
        assistant: assistant,
        tool_results: [tr]
      }

      assert Turn.flatten(turn) == [assistant, tr]
    end

    test "tool_results가 비어 있으면 injected + assistant만" do
      injected = [User.new("X")]
      assistant = %Assistant{content: [{:text, "y"}]}

      turn = %Turn{
        index: 1,
        injected: injected,
        assistant: assistant,
        tool_results: []
      }

      assert Turn.flatten(turn) == injected ++ [assistant]
    end

    test "injected와 tool_results 둘 다 비어 있으면 assistant만" do
      assistant = %Assistant{content: [{:text, "only"}]}

      turn = %Turn{index: 1, assistant: assistant}

      assert Turn.flatten(turn) == [assistant]
    end
  end
end
