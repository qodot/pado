defmodule Pado.AgentTest do
  use ExUnit.Case, async: true

  alias Pado.Agent
  alias Pado.Agent.Job
  alias Pado.AgentConfig
  alias Pado.AgentConfig.{Harness, LLM}
  alias Pado.LLM.Credential.OAuth.Credentials
  alias Pado.LLM.Model

  describe "handle_cast/2" do
    test ":abort_job은 실행 중인 job worker를 종료하고 aborted job_end를 보낸다" do
      {:ok, agent} = Agent.spawn(config())
      agent_ref = Process.monitor(agent)

      collector =
        Task.async(fn ->
          agent
          |> Pado.Stream.subscribe()
          |> Enum.to_list()
        end)

      assert :ok = wait_until_subscriber_count(agent, 1)

      worker = spawn(fn -> Process.sleep(:infinity) end)
      worker_ref = Process.monitor(worker)
      job_worker_monitor = Process.monitor(worker)

      :sys.replace_state(agent, fn state ->
        %{
          state
          | job: %Job{messages: [], session_id: "s1", job_id: "j1"},
            job_worker_pid: worker,
            job_worker_monitor: job_worker_monitor
        }
      end)

      GenServer.cast(agent, :abort_job)

      assert_receive {:DOWN, ^worker_ref, :process, ^worker, :shutdown}, 500

      assert [{:job_end, %{job_id: "j1", status: :aborted, reason: nil, turns: []}}] =
               Task.await(collector, 500)

      assert_receive {:DOWN, ^agent_ref, :process, ^agent, :normal}, 500
    end
  end

  defp wait_until_subscriber_count(pid, count, retries \\ 50)

  defp wait_until_subscriber_count(_pid, _count, 0), do: :error

  defp wait_until_subscriber_count(pid, count, retries) do
    case :sys.get_state(pid) do
      %{subscribers: subscribers} when map_size(subscribers) == count ->
        :ok

      _ ->
        Process.sleep(10)
        wait_until_subscriber_count(pid, count, retries - 1)
    end
  end

  defp config do
    %AgentConfig{
      llm: %LLM{
        provider: :openai_codex,
        credentials: Credentials.build(:openai_codex, "a", "r", 3600),
        model: %Model{id: "test", provider: :test}
      },
      harness: %Harness{}
    }
  end
end
