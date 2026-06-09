defmodule Pado.Agent.JobTest do
  use ExUnit.Case, async: true

  alias Pado.Agent.{Job, Session, Turn}
  alias Pado.Agent.Session.Entry
  alias Pado.LLM.Message.{Assistant, ToolResult, User}

  describe "build/1" do
    test "세션으로 실행 job을 만든다" do
      user = User.new("hi")

      session = %{
        Session.new("s1", cwd: "/tmp/pado", timestamp: now())
        | entries: [entry(:user, user, 0)]
      }

      assert %Job{
               messages: [^user],
               session_id: "s1",
               cwd: "/tmp/pado",
               job_id: "job-" <> _,
               max_turns: 10
             } = Job.build(session)
    end
  end

  describe "abort/3" do
    test "worker 프로세스를 종료하고 monitor DOWN 메시지를 flush한다" do
      worker = spawn(fn -> Process.sleep(:infinity) end)
      monitor_ref = Process.monitor(worker)

      assert :ok = Job.abort(build_job(), worker, monitor_ref)
      refute Process.alive?(worker)
      refute_receive {:DOWN, ^monitor_ref, :process, ^worker, _}, 50
    end

    test "실행 중인 tool abort를 실행한다" do
      parent = self()
      tool_task = Task.async(fn -> Process.sleep(:infinity) end)
      worker = spawn(fn -> Process.sleep(:infinity) end)
      monitor_ref = Process.monitor(worker)

      job = %{
        build_job()
        | running_tools: %{
            "c1" => %{
              task: tool_task,
              abort: fn task ->
                send(parent, {:tool_aborted, task.pid})
                Task.shutdown(task, :brutal_kill)
              end
            }
          }
      }

      assert :ok = Job.abort(job, worker, monitor_ref)
      assert_receive {:tool_aborted, pid} when pid == tool_task.pid
      refute Process.alive?(tool_task.pid)
    end
  end

  describe "running_tools" do
    test "기본값은 빈 맵이다" do
      assert %Job{running_tools: %{}} = build_job()
    end

    test "실행 중인 tool task를 등록하고 제거한다" do
      task = Task.async(fn -> :ok end)
      call = %{id: "c1", name: "echo"}

      abort = fn _ -> :ok end
      job = build_job() |> Job.start_tool(call, task, abort)

      assert job.running_tools == %{
               "c1" => %{
                 id: "c1",
                 name: "echo",
                 task: task,
                 pid: task.pid,
                 ref: task.ref,
                 abort: abort
               }
             }

      assert %{running_tools: %{}} = Job.finish_tool(job, "c1")
      assert :ok = Task.await(task)
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

  defp entry(kind, payload, seq) do
    %Entry{
      id: "entry-#{seq}",
      seq: seq,
      kind: kind,
      payload: payload,
      timestamp: now()
    }
  end

  defp now, do: ~U[2026-05-17 12:00:00Z]
end
