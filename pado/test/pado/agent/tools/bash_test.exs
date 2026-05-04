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
      assert schema.parameters["properties"]["timeout"]["type"] == "integer"
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

    test "args의 timeout을 넘기면 그 시간 안에 끝나지 않는 명령은 잘린다" do
      %AgentTool{execute: execute} = Bash.tool()
      result = execute.(%{"command" => "sleep 5", "timeout" => 1}, %{})

      assert result == "Command timed out after 1 seconds"
    end

    test "factory의 :timeout 기본값을 override할 수 있다" do
      %AgentTool{execute: execute} = Bash.tool(timeout: 1)
      result = execute.(%{"command" => "sleep 5"}, %{})

      assert result == "Command timed out after 1 seconds"
    end
  end

  describe "execute / 출력 truncation" do
    test "짧은 출력은 그대로 반환된다 (notice 없음)" do
      %AgentTool{execute: execute} = Bash.tool()
      result = execute.(%{"command" => "echo hello"}, %{})

      refute result =~ "Showing last"
      refute result =~ "Full output:"
    end

    test "200줄 넘는 출력은 마지막 부분만 보내고 안내가 붙는다" do
      %AgentTool{execute: execute} = Bash.tool()

      result =
        execute.(
          %{"command" => "for i in $(seq 1 250); do echo line$i; done"},
          %{}
        )

      assert result =~ "line250"
      refute result =~ "line1\n"
      assert result =~ "Showing last"
      assert result =~ "of 251 lines"
      assert result =~ "Full output:"
    end

    test "잘릴 때 전체 출력은 임시파일에 저장된다" do
      %AgentTool{execute: execute} = Bash.tool()

      result =
        execute.(
          %{"command" => "for i in $(seq 1 250); do echo line$i; done"},
          %{}
        )

      [_, path] = Regex.run(~r{Full output: ([^\s\]]+)}, result)
      assert File.exists?(path)
      full = File.read!(path)
      assert String.contains?(full, "line1\n")
      assert String.contains?(full, "line250\n")
      File.rm!(path)
    end
  end
end
