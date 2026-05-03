defmodule Pado.Agent.LoopTest do
  use ExUnit.Case, async: true

  alias Pado.Agent.{Job, Loop, Turn}
  alias Pado.LLM.{Context, Model}
  alias Pado.LLM.Message.{Assistant, User}

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

  defp build_job(opts) do
    %Job{
      model: %Model{id: "test", provider: :test},
      credential_provider: :test_provider,
      session_id: "s1",
      context: Context.new(messages: [User.new("hi")]),
      job_id: "j1",
      turns: Keyword.get(opts, :turns, []),
      max_turns: Keyword.get(opts, :max_turns, 10),
      tools: Keyword.get(opts, :tools, [])
    }
  end

  defp with_tool_call do
    %Assistant{content: [{:tool_call, %{id: "c1", name: "any", args: %{}}}]}
  end
end
