defmodule Pado.Agent.JobTest do
  use ExUnit.Case, async: true

  alias Pado.Agent.{Job, Turn}
  alias Pado.LLM.Message.{Assistant, ToolResult, User}

  describe "next_step/1" do
    test "turns가 비어 있으면 :done (방어적 default)" do
      assert Job.next_step(build_job(turns: [])) == :done
    end

    test "turns 길이가 max_turns에 도달하면 :max_turns" do
      job =
        build_job(
          max_turns: 2,
          turns: [
            %Turn{index: 1, assistant: with_tool_call()},
            %Turn{index: 2, assistant: with_tool_call()}
          ]
        )

      assert Job.next_step(job) == :max_turns
    end

    test "turns 길이가 max_turns를 초과해도 :max_turns" do
      job =
        build_job(
          max_turns: 1,
          turns: [
            %Turn{index: 1, assistant: with_tool_call()},
            %Turn{index: 2, assistant: with_tool_call()}
          ]
        )

      assert Job.next_step(job) == :max_turns
    end

    test "마지막 turn에 tool_call이 있고 max_turns 안 도달이면 :continue" do
      job =
        build_job(
          max_turns: 5,
          turns: [%Turn{index: 1, assistant: with_tool_call()}]
        )

      assert Job.next_step(job) == :continue
    end

    test "마지막 turn에 tool_call이 없고 max_turns 안 도달이면 :done" do
      job =
        build_job(
          max_turns: 5,
          turns: [%Turn{index: 1, assistant: %Assistant{content: [{:text, "끝"}]}}]
        )

      assert Job.next_step(job) == :done
    end
  end

  defp with_tool_call do
    %Assistant{content: [{:tool_call, %{id: "c1", name: "any", args: %{}}}]}
  end

  describe "llm_messages/1" do
    test "turns가 비어 있으면 job.messages 그대로" do
      base = [User.new("first")]
      job = build_job(messages: base)

      assert Job.llm_messages(job) == base
    end

    test "turns가 있으면 base 뒤에 각 turn의 as_llm_messages가 순서대로 이어진다" do
      base = [User.new("first")]
      asst = %Assistant{content: [{:text, "ok"}]}
      tr = ToolResult.text("c1", "echo", "hi")

      turn = %Turn{
        index: 1,
        assistant: asst,
        tool_results: [tr]
      }

      job = %{build_job(messages: base) | turns: [turn]}

      assert Job.llm_messages(job) == base ++ [asst, tr]
    end

    test "여러 turn이 있으면 turn 순서대로 평탄화" do
      asst1 = %Assistant{content: [{:text, "1"}]}
      asst2 = %Assistant{content: [{:text, "2"}]}

      job = %{
        build_job()
        | turns: [
            %Turn{index: 1, assistant: asst1},
            %Turn{index: 2, assistant: asst2}
          ]
      }

      assert Job.llm_messages(job) == job.messages ++ [asst1, asst2]
    end
  end

  defp build_job(opts \\ []) do
    %Job{
      messages: Keyword.get(opts, :messages, [User.new("base")]),
      session_id: "s1",
      job_id: "j1",
      turns: Keyword.get(opts, :turns, []),
      max_turns: Keyword.get(opts, :max_turns, 10)
    }
  end
end
