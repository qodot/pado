defmodule Pado.AgentConfigTest do
  use ExUnit.Case, async: true

  alias Pado.Agent.Job
  alias Pado.AgentConfig
  alias Pado.AgentConfig.Tools.Tool, as: AgentTool
  alias Pado.LLM.{Context, Model, Tool}
  alias Pado.LLM.Credential.OAuth.Credentials
  alias Pado.LLM.Message.User

  describe "build/5" do
    test "provider, credentials, model, reasoning_effort로 기본 설정을 만든다" do
      credentials = Credentials.build(:openai_codex, "a", "r", 3600)
      model = %Model{id: "codex", provider: :openai_codex}

      assert %AgentConfig{
               llm: %AgentConfig.LLM{
                 provider: :openai_codex,
                 credentials: ^credentials,
                 model: ^model,
                 router: Pado.LLM,
                 opts: [reasoning_effort: :high]
               },
               harness: %AgentConfig.Harness{tools: [tool]}
             } = AgentConfig.build(:openai_codex, credentials, model, :high)

      assert tool.schema.name == "bash"
    end

    test "reasoning_effort가 nil이면 opts를 비운다" do
      credentials = Credentials.build(:openai_codex, "a", "r", 3600)
      model = %Model{id: "codex", provider: :openai_codex}

      assert %AgentConfig{llm: %AgentConfig.LLM{opts: []}} =
               AgentConfig.build(:openai_codex, credentials, model, nil)
    end

    test "지원하지 않는 provider는 받지 않는다" do
      credentials = Credentials.build(:unknown, "a", "r", 3600)
      model = %Model{id: "codex", provider: :unknown}

      assert_raise FunctionClauseError, fn ->
        apply(AgentConfig, :build, [:unknown, credentials, model, :high])
      end
    end

    test "router와 tools를 옵션으로 바꿀 수 있다" do
      credentials = Credentials.build(:openai_codex, "a", "r", 3600)
      model = %Model{id: "codex", provider: :openai_codex}

      tool = %AgentTool{
        schema: Tool.new("echo", "d", %{}),
        async: fn _, _, _ -> Task.async(fn -> "ok" end) end,
        abort: fn task -> Task.shutdown(task, :brutal_kill) end
      }

      assert %AgentConfig{
               llm: %AgentConfig.LLM{router: String},
               harness: %AgentConfig.Harness{tools: [^tool]}
             } =
               AgentConfig.build(:openai_codex, credentials, model, :low,
                 router: String,
                 tools: [tool]
               )
    end
  end

  describe "llm_context/2" do
    test "harness와 job을 LLM context로 변환한다" do
      user = User.new("hi")
      tool_schema = Tool.new("echo", "d", %{})

      config = %AgentConfig{
        llm: %AgentConfig.LLM{
          provider: :openai_codex,
          credentials: Credentials.build(:openai_codex, "a", "r", 3600),
          model: %Model{id: "test", provider: :test}
        },
        harness: %AgentConfig.Harness{
          system_prompt: "system",
          tools: [
            %AgentTool{
              schema: tool_schema,
              async: fn _, _, _ -> Task.async(fn -> "ok" end) end,
              abort: fn task -> Task.shutdown(task, :brutal_kill) end
            }
          ]
        }
      }

      assert %Context{
               system_prompt: "system",
               messages: [^user],
               tools: [^tool_schema]
             } = AgentConfig.llm_context(config, %Job{messages: [user], session_id: "s1"})
    end
  end
end
