defmodule Pado.AgentTest do
  use ExUnit.Case, async: true

  alias Pado.Agent
  alias Pado.Agent.{Job, Tool, Turn}
  alias Pado.LLM.{Model, Usage}
  alias Pado.LLM.Credential.OAuth.Credentials
  alias Pado.LLM.Message.{Assistant, User}
  alias Pado.LLM.Tool, as: LLMTool

  describe "loop/2" do
    setup do
      test_pid = self()

      Pado.Test.FakeLLM.setup_owner()
      on_exit(fn -> Pado.Test.FakeLLM.cleanup_owner(test_pid) end)

      :ok
    end

    test "1턴 정상 응답 → :job_start로 시작해서 :job_end status :done으로 종료" do
      Pado.Test.FakeLLM.put_response(ok_stream(%Assistant{content: [{:text, "end"}]}))

      {agent, job} = build_setup([])
      events = Agent.loop(agent, job) |> Enum.to_list()

      assert {:job_start, %{job_id: "j1"}} = hd(events)
      assert {:job_end, %{status: :done, reason: nil, turns: [_]}} = List.last(events)
    end

    test "multi-turn (1턴 tool_call + 2턴 final) → turn_start 이벤트 2개" do
      tool = make_tool("echo", fn _, _ -> "r" end)

      asst1 = %Assistant{content: [{:tool_call, %{id: "c1", name: "echo", args: %{}}}]}
      asst2 = %Assistant{content: [{:text, "final"}]}
      Pado.Test.FakeLLM.put_responses([ok_stream(asst1), ok_stream(asst2)])

      {agent, job} = build_setup(tools: [tool])
      events = Agent.loop(agent, job) |> Enum.to_list()

      turn_starts = Enum.filter(events, &match?({:turn_start, _}, &1))
      assert length(turn_starts) == 2

      assert {:job_end, %{status: :done, turns: [_, _]}} = List.last(events)
    end
  end

  describe "run_loop/3" do
    setup do
      test_pid = self()
      emit = fn ev -> send(test_pid, {:emitted, ev}) end

      Pado.Test.FakeLLM.setup_owner()
      on_exit(fn -> Pado.Test.FakeLLM.cleanup_owner(test_pid) end)

      {:ok, emit: emit}
    end

    test "1턴에 final 응답이면 :done으로 종료", %{emit: emit} do
      Pado.Test.FakeLLM.put_response(ok_stream(%Assistant{content: [{:text, "end"}]}))

      {agent, job} = build_setup([])
      assert {%Job{turns: [_]}, :done, nil} = Agent.run_loop(agent, job, emit)

      assert_received {:emitted, {:turn_start, %{turn_index: 1}}}
      assert_received {:emitted, {:turn_end, %{turn: %Turn{index: 1}}}}
    end

    test "1턴 tool_call + 2턴 final 이면 2턴 후 :done", %{emit: emit} do
      tool = make_tool("echo", fn _, _ -> "r" end)

      asst1 = %Assistant{content: [{:tool_call, %{id: "c1", name: "echo", args: %{}}}]}
      asst2 = %Assistant{content: [{:text, "final"}]}

      Pado.Test.FakeLLM.put_responses([ok_stream(asst1), ok_stream(asst2)])

      {agent, job} = build_setup(tools: [tool])
      assert {%Job{turns: turns}, :done, nil} = Agent.run_loop(agent, job, emit)
      assert length(turns) == 2

      assert_received {:emitted, {:turn_start, %{turn_index: 1}}}
      assert_received {:emitted, {:turn_start, %{turn_index: 2}}}
    end

    test "max_turns에 도달하면 :max_turns", %{emit: emit} do
      tool = make_tool("echo", fn _, _ -> "r" end)

      asst = %Assistant{content: [{:tool_call, %{id: "c1", name: "echo", args: %{}}}]}
      Pado.Test.FakeLLM.put_response(ok_stream(asst))

      {agent, job} = build_setup(max_turns: 1, tools: [tool])
      assert {%Job{turns: [_]}, :max_turns, nil} = Agent.run_loop(agent, job, emit)
    end

    test "LLM 응답이 :error로 끝나면 :error 상태로 종료 + reason은 error_message", %{emit: emit} do
      error_msg = %Assistant{stop_reason: :error, error_message: "boom"}

      Pado.Test.FakeLLM.put_response(
        {:ok,
         [
           {:start, %{message: %Assistant{}}},
           {:error,
            %{reason: :error, error_message: "boom", message: error_msg, usage: Usage.empty()}}
         ]}
      )

      {agent, job} = build_setup([])
      assert {%Job{turns: [_]}, :error, "boom"} = Agent.run_loop(agent, job, emit)
    end
  end

  defp build_setup(opts) do
    agent = %Agent{
      llm: %Pado.Agent.LLM{
        provider: :openai_codex,
        credentials: Credentials.build(:openai_codex, "a", "r", 3600),
        model: %Model{id: "test", provider: :test}
      },
      harness: %Pado.Agent.Harness{
        tools: Keyword.get(opts, :tools, [])
      }
    }

    job = %Job{
      messages: [User.new("hi")],
      session_id: "s1",
      job_id: "j1",
      turns: Keyword.get(opts, :turns, []),
      max_turns: Keyword.get(opts, :max_turns, 10)
    }

    {agent, job}
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
