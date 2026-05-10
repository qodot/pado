defmodule Pado.AgentTest do
  use ExUnit.Case, async: true

  alias Pado.Agent
  alias Pado.Agent.Job
  alias Pado.AgentConfig
  alias Pado.AgentConfig.Tools.Tool
  alias Pado.LLM.{Model, Usage}
  alias Pado.LLM.Credential.OAuth.Credentials
  alias Pado.LLM.Message.{Assistant, User}
  alias Pado.LLM.Tool, as: LLMTool

  setup do
    test_pid = self()

    Pado.Test.FakeLLM.setup_owner()
    on_exit(fn -> Pado.Test.FakeLLM.cleanup_owner(test_pid) end)

    :ok
  end

  describe "spawn/1 + stream/2 정상 종료 경로" do
    test "1턴 응답 → :job_start로 시작, :job_end status :done" do
      Pado.Test.FakeLLM.put_response(ok_stream(%Assistant{content: [{:text, "ok"}]}))

      {config, job} = build_setup([])
      {:ok, agent} = Agent.spawn(config)
      {:ok, stream} = Agent.stream(agent, job)

      events = Enum.to_list(stream)

      assert {:job_start, %{job_id: "j1"}} = hd(events)
      assert {:job_end, %{status: :done, reason: nil, turns: [_]}} = List.last(events)
    end

    test "tool_call 후 다음 turn → turn_start 2번, :done으로 종료" do
      tool = make_tool("echo", fn _, _ -> "r" end)

      asst1 = %Assistant{content: [{:tool_call, %{id: "c1", name: "echo", args: %{}}}]}
      asst2 = %Assistant{content: [{:text, "final"}]}
      Pado.Test.FakeLLM.put_responses([ok_stream(asst1), ok_stream(asst2)])

      {config, job} = build_setup(tools: [tool])
      {:ok, agent} = Agent.spawn(config)
      {:ok, stream} = Agent.stream(agent, job)

      events = Enum.to_list(stream)

      turn_starts = Enum.filter(events, &match?({:turn_start, _}, &1))
      assert length(turn_starts) == 2

      assert {:job_end, %{status: :done, turns: [_, _]}} = List.last(events)
    end

    test "max_turns 도달 시 :max_turns" do
      tool = make_tool("echo", fn _, _ -> "r" end)
      asst = %Assistant{content: [{:tool_call, %{id: "c1", name: "echo", args: %{}}}]}
      Pado.Test.FakeLLM.put_response(ok_stream(asst))

      {config, job} = build_setup(max_turns: 1, tools: [tool])
      {:ok, agent} = Agent.spawn(config)
      {:ok, stream} = Agent.stream(agent, job)

      events = Enum.to_list(stream)
      assert {:job_end, %{status: :max_turns, turns: [_]}} = List.last(events)
    end

    test "LLM 응답이 :error로 끝나면 :job_end status :error에 reason 실림" do
      error_msg = %Assistant{stop_reason: :error, error_message: "boom"}

      Pado.Test.FakeLLM.put_response(
        {:ok,
         [
           {:start, %{message: %Assistant{}}},
           {:error,
            %{reason: :error, error_message: "boom", message: error_msg, usage: Usage.empty()}}
         ]}
      )

      {config, job} = build_setup([])
      {:ok, agent} = Agent.spawn(config)
      {:ok, stream} = Agent.stream(agent, job)

      assert {:job_end, %{status: :error, reason: "boom"}} =
               stream |> Enum.to_list() |> List.last()
    end
  end

  describe "stream/2 라이프사이클 enforcement" do
    test "stream/2를 여러 번 호출하면 각각 구독 스트림을 반환한다" do
      {config, job} = build_setup([])
      {:ok, agent} = Agent.spawn(config)

      assert {:ok, _stream1} = Agent.stream(agent, job)
      assert {:ok, _stream2} = Agent.stream(agent, job)

      Process.exit(agent, :kill)
    end

    test "이미 종료된 agent에 stream/2를 호출하면 에러 종료 이벤트 스트림을 반환한다" do
      Pado.Test.FakeLLM.put_response(ok_stream(%Assistant{content: [{:text, "ok"}]}))

      {config, job} = build_setup([])
      {:ok, agent} = Agent.spawn(config)
      {:ok, stream} = Agent.stream(agent, job)
      _ = Enum.to_list(stream)

      wait_until_dead(agent)

      assert {:ok, stream} = Agent.stream(agent, job)
      assert [{:job_end, %{job_id: nil, status: :error, turns: []}}] = Enum.to_list(stream)
    end
  end

  describe "구독자 라이프사이클" do
    test "여러 구독자가 같은 job의 이후 이벤트를 받는다" do
      Pado.Test.FakeLLM.put_response(
        gated_ok_stream(self(), %Assistant{content: [{:text, "ok"}]})
      )

      {config, job} = build_setup([])
      {:ok, agent} = Agent.spawn(config)

      subscriber1 =
        Task.async(fn ->
          {:ok, stream} = Agent.stream(agent, job)
          Enum.to_list(stream)
        end)

      assert_receive {:llm_stream_waiting, worker_pid}, 500

      subscriber2 =
        Task.async(fn ->
          {:ok, stream} = Agent.stream(agent, job)
          Enum.to_list(stream)
        end)

      assert :ok = wait_until_subscriber_count(agent, 2)

      send(worker_pid, :release_llm_stream)

      events1 = Task.await(subscriber1, 500)
      events2 = Task.await(subscriber2, 500)

      assert {:job_end, %{status: :done}} = List.last(events1)
      assert {:job_end, %{status: :done}} = List.last(events2)

      assert Enum.any?(events1, &match?({:message_start, _}, &1))
      assert Enum.any?(events2, &match?({:message_start, _}, &1))
    end

    test "구독자 하나가 죽어도 다른 구독자가 남아 있으면 agent는 유지된다" do
      Pado.Test.FakeLLM.put_response(
        gated_ok_stream(self(), %Assistant{content: [{:text, "ok"}]})
      )

      {config, job} = build_setup([])
      {:ok, agent} = Agent.spawn(config)

      live_subscriber =
        Task.async(fn ->
          {:ok, stream} = Agent.stream(agent, job)
          Enum.to_list(stream)
        end)

      assert_receive {:llm_stream_waiting, worker_pid}, 500

      dead_subscriber =
        spawn(fn ->
          {:ok, stream} = Agent.stream(agent, job)
          Enum.to_list(stream)
        end)

      assert :ok = wait_until_subscriber_count(agent, 2)

      dead_ref = Process.monitor(dead_subscriber)
      Process.exit(dead_subscriber, :kill)
      assert_receive {:DOWN, ^dead_ref, :process, ^dead_subscriber, :killed}, 500

      assert :ok = wait_until_subscriber_count(agent, 1)
      assert Process.alive?(agent)

      send(worker_pid, :release_llm_stream)

      assert {:job_end, %{status: :done}} = live_subscriber |> Task.await(500) |> List.last()
    end

    test "마지막 구독자가 stream을 중단하면 agent도 정리된다" do
      Pado.Test.FakeLLM.put_response(
        gated_ok_stream(self(), %Assistant{content: [{:text, "ok"}]})
      )

      {config, job} = build_setup([])
      {:ok, agent} = Agent.spawn(config)
      {:ok, stream} = Agent.stream(agent, job)

      assert [{:job_start, %{job_id: "j1"}}] = Enum.take(stream, 1)

      ref = Process.monitor(agent)
      assert_receive {:DOWN, ^ref, :process, ^agent, _}, 500
    end
  end

  defp wait_until_dead(pid, retries \\ 50)

  defp wait_until_dead(_pid, 0), do: :error

  defp wait_until_dead(pid, retries) do
    if Process.alive?(pid) do
      Process.sleep(10)
      wait_until_dead(pid, retries - 1)
    else
      :ok
    end
  end

  defp wait_until_subscriber_count(pid, count, retries \\ 50)

  defp wait_until_subscriber_count(_pid, _count, 0), do: :error

  defp wait_until_subscriber_count(pid, count, retries) do
    try do
      case :sys.get_state(pid) do
        %{subscribers: subscribers} when map_size(subscribers) == count ->
          :ok

        _ ->
          Process.sleep(10)
          wait_until_subscriber_count(pid, count, retries - 1)
      end
    catch
      :exit, _ -> :error
    end
  end

  defp build_setup(opts) do
    config = %AgentConfig{
      llm: %AgentConfig.LLM{
        provider: :openai_codex,
        credentials: Credentials.build(:openai_codex, "a", "r", 3600),
        model: %Model{id: "test", provider: :test}
      },
      harness: %AgentConfig.Harness{
        tools: Keyword.get(opts, :tools, [])
      }
    }

    job = %Job{
      messages: [User.new("hi")],
      session_id: "s1",
      job_id: "j1",
      max_turns: Keyword.get(opts, :max_turns, 10)
    }

    {config, job}
  end

  defp make_tool(name, execute) do
    %Tool{
      schema: LLMTool.new(name, "d", %{}),
      execute: execute
    }
  end

  defp ok_stream(final_assistant) do
    {:ok,
     [
       {:start, %{message: %Assistant{}}},
       {:done, %{stop_reason: :stop, usage: Usage.empty(), message: final_assistant}}
     ]}
  end

  defp gated_ok_stream(parent, final_assistant) do
    {:ok,
     Stream.resource(
       fn ->
         send(parent, {:llm_stream_waiting, self()})
         :waiting
       end,
       fn
         :waiting ->
           receive do
             :release_llm_stream ->
               {[
                  {:start, %{message: %Assistant{}}},
                  {:done, %{stop_reason: :stop, usage: Usage.empty(), message: final_assistant}}
                ], :done}
           end

         :done ->
           {:halt, :done}
       end,
       fn _ -> :ok end
     )}
  end
end
