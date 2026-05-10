defmodule Pado.Agent.JobTest do
  use ExUnit.Case, async: true

  alias Pado.Agent.{Job, Turn}
  alias Pado.LLM.Message.{Assistant, ToolResult, User}

  describe "abort/2" do
    test "pid가 nil이면 아무 작업 없이 :ok를 반환한다" do
      assert :ok = Job.abort(nil, nil)
    end

    test "worker 프로세스를 종료하고 monitor DOWN 메시지를 flush한다" do
      worker = spawn(fn -> Process.sleep(:infinity) end)
      monitor_ref = Process.monitor(worker)

      assert :ok = Job.abort(worker, monitor_ref)
      refute Process.alive?(worker)
      refute_receive {:DOWN, ^monitor_ref, :process, ^worker, _}, 50
    end
  end

  describe "기본 상태" do
    test "running_tools는 빈 맵으로 시작한다" do
      assert %Job{running_tools: %{}} = build_job()
    end
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
