defmodule Pado.Agent.Session.CodecTest do
  use ExUnit.Case, async: true

  alias Pado.Agent.Session
  alias Pado.Agent.Session.{Codec, CompactionSummary, Entry, Error, ModelChange}
  alias Pado.LLM.Message.{Assistant, ToolResult, User}
  alias Pado.LLM.Usage

  @now ~U[2026-05-17 12:00:00Z]

  test "공개 API는 세션과 엔트리 map 변환만 노출한다" do
    assert Codec.__info__(:functions) |> Keyword.keys() |> Enum.sort() ==
             [:entry_from_map, :entry_to_map, :session_from_map, :session_to_map]
  end

  describe "session_to_map/1과 session_from_map/1" do
    test "세션 구조체를 저장 가능한 맵으로 왕복한다" do
      session =
        "session-1"
        |> Session.new(
          cwd: "/tmp/pado-workspace",
          provider: :openai_codex,
          model: "gpt-5.4",
          reasoning_effort: :high,
          timestamp: @now
        )
        |> Map.put(:entries, build_entries())

      assert {:ok, ^session} = session |> Codec.session_to_map() |> Codec.session_from_map()
    end

    test "세션 cwd를 저장 가능한 맵에 포함한다" do
      map =
        "session-1"
        |> Session.new(cwd: "/tmp/pado-workspace", timestamp: @now)
        |> Codec.session_to_map()

      assert map["cwd"] == "/tmp/pado-workspace"
    end

    test "type이 session이 아니면 에러를 반환한다" do
      assert {:error, {:invalid_session_map, %{"type" => "entry"}}} =
               Codec.session_from_map(%{"type" => "entry"})
    end

    test "알 수 없는 provider 문자열이면 에러를 반환한다" do
      map =
        Session.new("session-1", timestamp: @now)
        |> Codec.session_to_map()
        |> Map.put("provider", "missing_session_provider")

      assert {:error, {:unknown_provider, "missing_session_provider"}} =
               Codec.session_from_map(map)
    end

    test "알 수 없는 reasoning effort 문자열이면 에러를 반환한다" do
      map =
        Session.new("session-1", timestamp: @now)
        |> Codec.session_to_map()
        |> Map.put("reasoning_effort", "extreme")

      assert {:error, {:unknown_reasoning_effort, "extreme"}} = Codec.session_from_map(map)
    end
  end

  describe "entry_to_map/1과 entry_from_map/1" do
    test "엔트리 구조체를 저장 가능한 맵으로 왕복한다" do
      for entry <- build_entries() do
        assert {:ok, ^entry} = entry |> Codec.entry_to_map() |> Codec.entry_from_map()
      end
    end

    test "type이 entry가 아니면 에러를 반환한다" do
      assert {:error, {:invalid_entry_map, %{"type" => "session"}}} =
               Codec.entry_from_map(%{"type" => "session"})
    end

    test "기존 model_change 엔트리는 reasoning effort 없이도 읽는다" do
      map = %{
        "type" => "entry",
        "id" => "entry-1",
        "seq" => 0,
        "kind" => "model_change",
        "payload" => %{
          "provider" => "openai_codex",
          "from" => "gpt-5.3",
          "to" => "gpt-5.4"
        },
        "refs" => %{},
        "timestamp" => DateTime.to_iso8601(@now)
      }

      assert {:ok,
              %Entry{
                payload: %ModelChange{
                  provider: :openai_codex,
                  from: "gpt-5.3",
                  to: "gpt-5.4",
                  reasoning_effort: nil
                }
              }} = Codec.entry_from_map(map)
    end

    test "model_change의 알 수 없는 reasoning effort 문자열이면 에러를 반환한다" do
      map = %{
        "type" => "entry",
        "id" => "entry-1",
        "seq" => 0,
        "kind" => "model_change",
        "payload" => %{
          "provider" => "openai_codex",
          "from" => "gpt-5.3",
          "to" => "gpt-5.4",
          "reasoning_effort" => "extreme"
        },
        "refs" => %{},
        "timestamp" => DateTime.to_iso8601(@now)
      }

      assert {:error, {:unknown_reasoning_effort, "extreme"}} = Codec.entry_from_map(map)
    end
  end

  defp build_entries do
    [
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
        payload: %ModelChange{
          provider: :openai_codex,
          from: "gpt-5.3",
          to: "gpt-5.4",
          reasoning_effort: :high
        },
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
  end
end
