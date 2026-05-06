defmodule Pado.AgentConfigTest do
  use ExUnit.Case, async: true

  alias Pado.Agent.Job
  alias Pado.AgentConfig
  alias Pado.AgentConfig.Tools.Tool, as: AgentTool
  alias Pado.LLM.{Context, Model, Tool}
  alias Pado.LLM.Credential.OAuth.Credentials
  alias Pado.LLM.Message.User

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
              execute: fn _, _ -> "ok" end
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
