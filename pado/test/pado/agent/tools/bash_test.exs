defmodule Pado.Agent.Tools.BashTest do
  use ExUnit.Case, async: true

  alias Pado.Agent.Tools.Tool, as: AgentTool
  alias Pado.LLM.Tool, as: LLMTool
  alias Pado.Agent.Tools.Bash

  describe "tool/0" do
    test "schema의 name은 \"bash\"이고 command는 required다" do
      %AgentTool{schema: %LLMTool{} = schema} = Bash.tool()

      assert schema.name == "bash"
      assert schema.parameters["required"] == ["command"]
      assert schema.parameters["properties"]["command"]["type"] == "string"
    end
  end

  describe "execute" do
    test "정상 명령은 exit_code 0과 출력을 함께 반환한다" do
      %AgentTool{execute: execute} = Bash.tool()
      result = execute.(%{"command" => "echo hello"}, %{})

      assert result =~ "exit_code: 0"
      assert result =~ "hello"
    end

    test "실패 명령은 0이 아닌 exit_code를 담아 반환한다" do
      %AgentTool{execute: execute} = Bash.tool()
      result = execute.(%{"command" => "false"}, %{})

      assert result =~ ~r/exit_code: [^0]/
    end

    test "stderr도 출력에 합쳐진다" do
      %AgentTool{execute: execute} = Bash.tool()
      result = execute.(%{"command" => "echo err 1>&2"}, %{})

      assert result =~ "exit_code: 0"
      assert result =~ "err"
    end
  end
end
