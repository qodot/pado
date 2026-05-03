defmodule Pado.Agent.JobTest do
  use ExUnit.Case, async: true

  alias Pado.Agent.{Job, Turn}
  alias Pado.LLM.Model
  alias Pado.LLM.Credential.OAuth.Credentials
  alias Pado.LLM.Message.{Assistant, ToolResult, User}

  describe "llm_context/1" do
    test "agent.system_prompt가 ctx.system_prompt에 들어간다" do
      job = build_job(system_prompt: "sys")
      assert Job.llm_context(job).system_prompt == "sys"
    end

    test "messages와 tools도 함께 채워진다" do
      tool = %Pado.Agent.Tool{
        schema: Pado.LLM.Tool.new("search", "d", %{}),
        execute: fn _, _ -> "" end
      }

      asst = %Assistant{content: [{:text, "a"}]}
      base_msgs = [User.new("first")]

      job = %{
        build_job(messages: base_msgs, tools: [tool])
        | turns: [%Turn{index: 1, assistant: asst}]
      }

      ctx = Job.llm_context(job)
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

      job = build_job(tools: [tool_a, tool_b])
      assert Job.llm_tools(job) == [tool_a.schema, tool_b.schema]
    end

    test "tools가 비어 있으면 빈 리스트" do
      job = build_job()
      assert Job.llm_tools(job) == []
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
        users: [],
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
    agent = %Pado.Agent{
      llm: %Pado.Agent.LLM{
        provider: :openai_codex,
        credentials: Credentials.build(:openai_codex, "a", "r", 3600),
        model: %Model{id: "test", provider: :test}
      },
      harness: %Pado.Agent.Harness{
        tools: Keyword.get(opts, :tools, []),
        system_prompt: Keyword.get(opts, :system_prompt)
      }
    }

    %Job{
      agent: agent,
      messages: Keyword.get(opts, :messages, [User.new("base")]),
      session_id: "s1",
      job_id: "j1"
    }
  end
end
