defmodule Pado.Agent.SessionTest do
  use ExUnit.Case, async: true

  alias Pado.Agent.Session
  alias Pado.Agent.Session.{Entry, Error, ModelChange}
  alias Pado.LLM.Message.{Assistant, ToolResult, User}

  @now ~U[2026-05-17 12:00:00Z]

  describe "new/2" do
    test "생성 시 현재 모델과 reasoning effort를 지정한다" do
      assert %Session{
               id: "session-1",
               provider: :openai_codex,
               model: "gpt-5.4",
               reasoning_effort: :high,
               created_at: @now,
               updated_at: @now,
               entries: []
             } =
               Session.new("session-1",
                 provider: :openai_codex,
                 model: "gpt-5.4",
                 reasoning_effort: :high,
                 timestamp: @now
               )
    end
  end

  describe "to_llm_messages/1" do
    test "LLM 메시지 엔트리만 순서대로 반환하고 로그 엔트리는 제외한다" do
      user = %User{content: "hello", timestamp: @now}
      assistant = %Assistant{content: [{:text, "hi"}], timestamp: @now}
      tool_result = %ToolResult{tool_call_id: "call-1", tool_name: "echo", timestamp: @now}

      session = %Session{
        id: "session-1",
        created_at: @now,
        updated_at: @now,
        entries: [
          %Entry{id: "entry-1", seq: 0, kind: :user, payload: user, timestamp: @now},
          %Entry{
            id: "entry-2",
            seq: 1,
            kind: :assistant,
            payload: assistant,
            timestamp: @now
          },
          %Entry{
            id: "entry-3",
            seq: 2,
            kind: :tool_result,
            payload: tool_result,
            timestamp: @now
          },
          %Entry{
            id: "entry-4",
            seq: 3,
            kind: :model_change,
            payload: %ModelChange{provider: :openai_codex, from: "gpt-5.3", to: "gpt-5.4"},
            timestamp: @now
          },
          %Entry{
            id: "entry-5",
            seq: 4,
            kind: :error,
            payload: %Error{message: "failed", reason: "timeout"},
            timestamp: @now
          }
        ]
      }

      assert Session.to_llm_messages(session) == [user, assistant, tool_result]
    end
  end

  describe "append_messages/3" do
    test "다음 seq부터 메시지 엔트리를 추가하고 updated_at을 갱신한다" do
      session = %Session{
        id: "session-1",
        created_at: @now,
        updated_at: @now,
        entries: [
          %Entry{
            id: "entry-1",
            seq: 0,
            kind: :user,
            payload: %User{content: "hello", timestamp: @now},
            timestamp: @now
          }
        ]
      }

      message = %Assistant{content: [{:text, "hi"}], timestamp: @now}
      later = ~U[2026-05-17 12:01:00Z]

      assert {%Session{updated_at: ^later, entries: entries}, [%Entry{} = entry]} =
               Session.append_messages(session, [message], timestamp: later)

      assert Enum.map(entries, & &1.seq) == [0, 1]
      assert %Entry{seq: 1, kind: :assistant, payload: ^message, timestamp: ^later} = entry
    end
  end
end
