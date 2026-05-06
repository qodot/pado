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
    test "stream/2를 두 번 호출하면 두 번째는 {:error, :not_spawning}" do
      Pado.Test.FakeLLM.put_response(ok_stream(%Assistant{content: [{:text, "ok"}]}))

      {config, job} = build_setup([])
      {:ok, agent} = Agent.spawn(config)
      {:ok, _stream1} = Agent.stream(agent, job)

      assert {:error, :not_spawning} = Agent.stream(agent, job)
    end

    test "이미 종료된 agent에 stream/2를 호출하면 {:error, :not_spawning}" do
      Pado.Test.FakeLLM.put_response(ok_stream(%Assistant{content: [{:text, "ok"}]}))

      {config, job} = build_setup([])
      {:ok, agent} = Agent.spawn(config)
      {:ok, stream} = Agent.stream(agent, job)
      _ = Enum.to_list(stream)

      # job 끝났으면 GenServer는 stop. 충분히 기다린 뒤 다시 호출.
      wait_until_dead(agent)

      assert {:error, :not_spawning} = Agent.stream(agent, job)
    end
  end

  describe "라이프사이클 monitor" do
    test "spawn한 owner가 죽으면 agent도 정리된다" do
      {config, _job} = build_setup([])
      test_pid = self()

      owner =
        spawn(fn ->
          {:ok, agent} = Agent.spawn(config)
          send(test_pid, {:agent, agent})
          # 곧장 종료 (정상)
        end)

      assert_receive {:agent, agent_pid}, 200
      ref = Process.monitor(agent_pid)
      assert_receive {:DOWN, ^ref, :process, ^agent_pid, _}, 500

      _ = owner
    end

    test "stream의 subscriber가 죽으면 agent도 정리된다" do
      Pado.Test.FakeLLM.put_response(ok_stream(%Assistant{content: [{:text, "ok"}]}))

      {config, job} = build_setup([])
      {:ok, agent} = Agent.spawn(config)

      test_pid = self()

      subscriber =
        spawn(fn ->
          {:ok, _stream} = Agent.stream(agent, job)
          send(test_pid, :subscribed)
          # stream을 enumerate하지 않고 즉시 종료
        end)

      assert_receive :subscribed, 200

      ref = Process.monitor(agent)
      assert_receive {:DOWN, ^ref, :process, ^agent, _}, 500

      _ = subscriber
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
end
