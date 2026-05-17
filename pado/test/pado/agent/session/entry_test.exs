defmodule Pado.Agent.Session.EntryTest do
  use ExUnit.Case, async: true

  alias Pado.Agent.Session
  alias Pado.Agent.Session.{CompactionSummary, Entry, Error, ModelChange}
  alias Pado.LLM.Message.{Assistant, ToolResult, User}
  alias Pado.LLM.Usage

  @now ~U[2026-05-17 12:00:00Z]

  describe "to_map/1과 from_map/1" do
    test "엔트리 구조체를 저장 가능한 맵으로 왕복한다" do
      for entry <- build_entries() do
        assert {:ok, ^entry} = entry |> Entry.to_map() |> Entry.from_map()
      end
    end

    test "type이 entry가 아니면 에러를 반환한다" do
      assert {:error, {:invalid_entry_map, %{"type" => "session"}}} =
               Entry.from_map(%{"type" => "session"})
    end
  end

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

  defp build_entries do
    %Session{
      id: "session-1",
      version: 1,
      created_at: @now,
      updated_at: @now,
      entries: [
        %Entry{
          id: "entry-1",
          seq: 0,
          kind: :user,
          payload: %User{content: "hello", timestamp: @now},
          timestamp: @now
        },
        %Entry{
          id: "entry-2",
          seq: 1,
          kind: :assistant,
          payload: %Assistant{
            content: [
              {:thinking, "checking"},
              {:text, "hi"},
              {:tool_call, %{id: "call-1", name: "echo", args: %{"text" => "hi"}}}
            ],
            stop_reason: :tool_use,
            usage: %Usage{
              input: 10,
              output: 5,
              cache_read: 1,
              cache_write: 2,
              total_tokens: 18,
              cost: %{input: 0.1, output: 0.2, cache_read: 0.01, cache_write: 0.02, total: 0.33}
            },
            provider: :openai_codex,
            model: "gpt-5.4",
            timestamp: @now
          },
          refs: %{"tool_call_ids" => ["call-1"]},
          timestamp: @now
        },
        %Entry{
          id: "entry-3",
          seq: 2,
          kind: :tool_result,
          payload: %ToolResult{
            tool_call_id: "call-1",
            tool_name: "echo",
            content: [{:text, "hi"}],
            timestamp: @now
          },
          refs: %{"tool_call_id" => "call-1"},
          timestamp: @now
        },
        %Entry{
          id: "entry-4",
          seq: 3,
          kind: :compaction_summary,
          payload: %CompactionSummary{
            summary: "이전 대화 요약",
            first_kept_seq: 2,
            tokens_before: 100
          },
          timestamp: @now
        },
        %Entry{
          id: "entry-5",
          seq: 4,
          kind: :model_change,
          payload: %ModelChange{provider: :openai_codex, from: "gpt-5.3", to: "gpt-5.4"},
          timestamp: @now
        },
        %Entry{
          id: "entry-6",
          seq: 5,
          kind: :error,
          payload: %Error{message: "failed", reason: "timeout"},
          timestamp: @now
        }
      ]
    }.entries
  end
end
