defmodule Pado.Agent.Session.EntryTest do
  use ExUnit.Case, async: true

  alias Pado.Agent.Session.Entry
  alias Pado.LLM.Message.{Assistant, ToolResult, User}

  @now ~U[2026-05-17 12:00:00Z]

  describe "from_message/3" do
    test "user 메시지를 user 엔트리로 만든다" do
      user = %User{content: "hello", timestamp: @now}

      assert %Entry{
               kind: :user,
               seq: 3,
               payload: ^user,
               refs: %{},
               timestamp: @now
             } = Entry.from_message(user, 3, timestamp: @now)
    end

    test "assistant tool_call id를 refs에 넣는다" do
      assistant = %Assistant{
        content: [
          {:tool_call, %{id: "call-1", name: "echo", args: %{}}},
          {:tool_call, %{id: "call-2", name: "read", args: %{}}}
        ]
      }

      assert %Entry{
               kind: :assistant,
               seq: 7,
               payload: ^assistant,
               refs: %{"tool_call_ids" => ["call-1", "call-2"]},
               timestamp: @now
             } = Entry.from_message(assistant, 7, timestamp: @now)
    end

    test "tool result의 tool_call_id를 refs에 넣는다" do
      result = %ToolResult{tool_call_id: "call-1", tool_name: "echo"}

      assert %Entry{
               kind: :tool_result,
               payload: ^result,
               refs: %{"tool_call_id" => "call-1"}
             } = Entry.from_message(result, 1, timestamp: @now)
    end
  end
end
