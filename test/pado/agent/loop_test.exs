defmodule Pado.Agent.LoopTest do
  use ExUnit.Case, async: true

  alias Pado.Agent.{Job, Loop, Tool, Turn}
  alias Pado.LLM.{Context, Model, Usage}
  alias Pado.LLM.Credential.OAuth.Credentials
  alias Pado.LLM.Message.{Assistant, User}
  alias Pado.LLM.Tool, as: LLMTool

  describe "next_step/1" do
    test "turns가 비어 있으면 :done (방어적 default)" do
      job = build_job(turns: [])
      assert Loop.next_step(job) == :done
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

      assert Loop.next_step(job) == :max_turns
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

      assert Loop.next_step(job) == :max_turns
    end

    test "마지막 turn에 tool_call이 있고 max_turns 안 도달이면 :continue" do
      job =
        build_job(
          max_turns: 5,
          turns: [%Turn{index: 1, assistant: with_tool_call()}]
        )

      assert Loop.next_step(job) == :continue
    end

    test "마지막 turn에 tool_call이 없고 max_turns 안 도달이면 :done" do
      job =
        build_job(
          max_turns: 5,
          turns: [%Turn{index: 1, assistant: %Assistant{content: [{:text, "끝"}]}}]
        )

      assert Loop.next_step(job) == :done
    end
  end

  describe "stream/1" do
    setup do
      test_pid = self()
      creds = Credentials.build(:openai_codex, "a", "r", 3600)

      Pado.Test.FakeLLM.setup_owner()
      Pado.Test.FakeCredsLoader.setup_owner()
      Pado.Test.FakeCredsLoader.put_response({:ok, creds})

      on_exit(fn ->
        Pado.Test.FakeLLM.cleanup_owner(test_pid)
        Pado.Test.FakeCredsLoader.cleanup_owner(test_pid)
      end)

      :ok
    end

    test "1턴 정상 응답 → :job_start로 시작해서 :job_end status :done으로 종료" do
      Pado.Test.FakeLLM.put_response(ok_stream(%Assistant{content: [{:text, "end"}]}))

      job = build_job([])
      events = Loop.stream(job) |> Enum.to_list()

      assert {:job_start, %{job_id: "j1"}} = hd(events)

      assert {:job_end, %{status: :done, reason: nil, turns: [_]}} = List.last(events)
    end

    test "multi-turn (1턴 tool_call + 2턴 final) → turn_start 이벤트 2개" do
      tool = make_tool("echo", fn _, _ -> "r" end)

      asst1 = %Assistant{content: [{:tool_call, %{id: "c1", name: "echo", args: %{}}}]}
      asst2 = %Assistant{content: [{:text, "final"}]}
      Pado.Test.FakeLLM.put_responses([ok_stream(asst1), ok_stream(asst2)])

      job = build_job(tools: [tool])
      events = Loop.stream(job) |> Enum.to_list()

      turn_starts = Enum.filter(events, &match?({:turn_start, _}, &1))
      assert length(turn_starts) == 2

      assert {:job_end, %{status: :done, turns: [_, _]}} = List.last(events)
    end

    test "credential 조회 실패 → :job_end status :error" do
      Pado.Test.FakeCredsLoader.put_response({:error, :token_expired})

      job = build_job([])
      events = Loop.stream(job) |> Enum.to_list()

      assert {:job_end, %{status: :error, reason: :token_expired, turns: []}} =
               List.last(events)
    end
  end

  describe "run_loop/2" do
    setup do
      test_pid = self()
      emit = fn ev -> send(test_pid, {:emitted, ev}) end
      creds = Credentials.build(:openai_codex, "a", "r", 3600)

      Pado.Test.FakeLLM.setup_owner()
      Pado.Test.FakeCredsLoader.setup_owner()
      Pado.Test.FakeCredsLoader.put_response({:ok, creds})

      on_exit(fn ->
        Pado.Test.FakeLLM.cleanup_owner(test_pid)
        Pado.Test.FakeCredsLoader.cleanup_owner(test_pid)
      end)

      {:ok, emit: emit, creds: creds}
    end

    test "1턴에 final 응답이면 :done으로 종료", %{emit: emit} do
      Pado.Test.FakeLLM.put_response(ok_stream(%Assistant{content: [{:text, "end"}]}))

      job = build_job([])
      assert {%Job{turns: [_]}, :done, nil} = Loop.run_loop(job, emit)

      assert_received {:emitted, {:turn_start, %{turn_index: 1}}}
      assert_received {:emitted, {:turn_end, %{turn: %Turn{index: 1}}}}
    end

    test "1턴 tool_call + 2턴 final 이면 2턴 후 :done", %{emit: emit} do
      tool = make_tool("echo", fn _, _ -> "r" end)

      asst1 = %Assistant{
        content: [{:tool_call, %{id: "c1", name: "echo", args: %{}}}]
      }

      asst2 = %Assistant{content: [{:text, "final"}]}

      Pado.Test.FakeLLM.put_responses([ok_stream(asst1), ok_stream(asst2)])

      job = build_job(tools: [tool])
      assert {%Job{turns: turns}, :done, nil} = Loop.run_loop(job, emit)
      assert length(turns) == 2

      assert_received {:emitted, {:turn_start, %{turn_index: 1}}}
      assert_received {:emitted, {:turn_start, %{turn_index: 2}}}
    end

    test "max_turns에 도달하면 :max_turns", %{emit: emit} do
      tool = make_tool("echo", fn _, _ -> "r" end)

      asst = %Assistant{content: [{:tool_call, %{id: "c1", name: "echo", args: %{}}}]}
      Pado.Test.FakeLLM.put_response(ok_stream(asst))

      job = build_job(max_turns: 1, tools: [tool])
      assert {%Job{turns: [_]}, :max_turns, nil} = Loop.run_loop(job, emit)
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

      job = build_job([])
      assert {%Job{turns: [_]}, :error, "boom"} = Loop.run_loop(job, emit)
    end

    test "credential 조회 실패는 :error 상태 + reason 그대로, turns는 추가 안 됨", %{emit: emit} do
      Pado.Test.FakeCredsLoader.put_response({:error, :token_expired})

      job = build_job([])
      assert {%Job{turns: []}, :error, :token_expired} = Loop.run_loop(job, emit)
    end
  end

  defp build_job(opts) do
    agent = %Pado.Agent{
      credential_provider: :test_provider,
      tools: Keyword.get(opts, :tools, [])
    }

    %Job{
      agent: agent,
      model: %Model{id: "test", provider: :test},
      session_id: "s1",
      context: Context.new(messages: [User.new("hi")]),
      job_id: "j1",
      turns: Keyword.get(opts, :turns, []),
      max_turns: Keyword.get(opts, :max_turns, 10)
    }
  end

  defp with_tool_call do
    %Assistant{content: [{:tool_call, %{id: "c1", name: "any", args: %{}}}]}
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
