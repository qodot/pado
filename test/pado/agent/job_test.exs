defmodule Pado.Agent.JobTest do
  use ExUnit.Case, async: true

  alias Pado.Agent.{Job, Turn}
  alias Pado.LLM.{Context, Model}
  alias Pado.LLM.Message.{Assistant, ToolResult, User}

  describe "llm_context/1" do
    test "job.context를 바탕으로 llm_messages와 llm_tools를 채워 반환" do
      tool = %Pado.Agent.Tool{
        schema: Pado.LLM.Tool.new("search", "d", %{}),
        execute: fn _, _ -> "" end
      }

      asst = %Assistant{content: [{:text, "a"}]}
      base_msgs = [User.new("first")]

      job = %{
        build_job(context: Context.new(messages: base_msgs, system_prompt: "sys"))
        | tools: [tool],
          turns: [%Turn{index: 1, assistant: asst}]
      }

      ctx = Job.llm_context(job)
      assert ctx.system_prompt == "sys"
      assert ctx.messages == base_msgs ++ [asst]
      assert ctx.tools == [tool.schema]
    end
  end

  describe "llm_tools/1" do
    test "job.tools에서 schema만 순서대로 추출" do
      tool_a = %Pado.Agent.Tool{
        schema: Pado.LLM.Tool.new("search", "d", %{}),
        execute: fn _, _ -> "a" end
      }

      tool_b = %Pado.Agent.Tool{
        schema: Pado.LLM.Tool.new("fetch", "d", %{}),
        execute: fn _, _ -> "b" end
      }

      job = %{build_job() | tools: [tool_a, tool_b]}
      assert Job.llm_tools(job) == [tool_a.schema, tool_b.schema]
    end

    test "tools가 비어 있으면 빈 리스트" do
      job = build_job()
      assert Job.llm_tools(job) == []
    end
  end

  describe "llm_messages/1" do
    test "turns가 비어 있으면 base context messages 그대로" do
      base = [User.new("first")]
      job = build_job(context: Context.new(messages: base))

      assert Job.llm_messages(job) == base
    end

    test "turns가 있으면 base 뒤에 각 turn의 as_llm_messages가 순서대로 이어진다" do
      base = [User.new("first")]
      asst = %Assistant{content: [{:text, "ok"}]}
      tr = ToolResult.text("c1", "echo", "hi")

      turn = %Turn{
        index: 1,
        users: [],
        assistant: asst,
        tool_results: [tr]
      }

      job = %{
        build_job(context: Context.new(messages: base))
        | turns: [turn]
      }

      assert Job.llm_messages(job) == base ++ [asst, tr]
    end

    test "여러 turn이 있으면 turn 순서대로 평탄화" do
      asst1 = %Assistant{content: [{:text, "1"}]}
      asst2 = %Assistant{content: [{:text, "2"}]}
      job = build_job()

      job = %{
        job
        | turns: [
            %Turn{index: 1, assistant: asst1},
            %Turn{index: 2, assistant: asst2}
          ]
      }

      assert Job.llm_messages(job) == job.context.messages ++ [asst1, asst2]
    end
  end

  defp build_job(opts \\ []) do
    %Job{
      model: %Model{id: "test", provider: :test},
      credential_provider: :test_provider,
      session_id: "s1",
      context: Keyword.get(opts, :context, Context.new(messages: [User.new("base")])),
      job_id: "j1"
    }
  end
end
