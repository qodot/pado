defmodule Pado.Agent.JobTest do
  use ExUnit.Case, async: true

  alias Pado.Agent.{Job, Turn}
  alias Pado.LLM.{Context, Model}
  alias Pado.LLM.Credential.OAuth.Credentials
  alias Pado.LLM.Message.{Assistant, ToolResult, User}

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
    creds = Credentials.build(:openai_codex, "a", "r", 3600)

    %Job{
      model: %Model{id: "test", provider: :test},
      credential_fun: fn -> {:ok, creds} end,
      session_id: "s1",
      context: Keyword.get(opts, :context, Context.new(messages: [User.new("base")])),
      job_id: "j1"
    }
  end
end
