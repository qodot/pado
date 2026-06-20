defmodule Pado.AgentConfig.Tools.BashTest do
  use ExUnit.Case, async: true

  alias Pado.AgentConfig.Tools.Tool, as: AgentTool
  alias Pado.AgentConfig.Tools.Tool.Result
  alias Pado.LLM.Tool, as: LLMTool
  alias Pado.AgentConfig.Tools.Bash

  describe "tool/0" do
    test "schema의 name은 \"bash\"이고 command는 required다" do
      %AgentTool{schema: %LLMTool{} = schema} = Bash.tool()

      assert schema.name == "bash"
      assert schema.parameters["required"] == ["command"]
      assert schema.parameters["properties"]["command"]["type"] == "string"
      assert schema.parameters["properties"]["timeout"]["type"] == "integer"
    end
  end

  describe "async" do
    test "정상 명령은 exit_code 0과 출력을 함께 반환한다" do
      %AgentTool{async: async} = Bash.tool()
      result = run_async(async, %{"command" => "echo hello"}, %{})

      assert result =~ "exit_code: 0"
      assert result =~ "hello"
    end

    test "실패 명령은 0이 아닌 exit_code를 담아 반환한다" do
      %AgentTool{async: async} = Bash.tool()
      result = run_async(async, %{"command" => "false"}, %{})

      assert result =~ ~r/exit_code: [^0]/
    end

    test "stderr도 출력에 합쳐진다" do
      %AgentTool{async: async} = Bash.tool()
      result = run_async(async, %{"command" => "echo err 1>&2"}, %{})

      assert result =~ "exit_code: 0"
      assert result =~ "err"
    end

    test "ctx의 cwd에서 명령을 실행한다" do
      directory = tmp_path("bash-cwd")
      File.mkdir_p!(directory)

      %AgentTool{async: async} = Bash.tool()
      result = run_async(async, %{"command" => "pwd"}, %{cwd: directory})

      assert result =~ "exit_code: 0"
      assert result =~ directory

      File.rm_rf!(directory)
    end

    test "args의 timeout을 넘기면 그 시간 안에 끝나지 않는 명령은 잘린다" do
      %AgentTool{async: async} = Bash.tool()
      result = run_async(async, %{"command" => "sleep 5", "timeout" => 1}, %{})

      assert result == "Command timed out after 1 seconds"
    end

    test "factory의 :timeout 기본값을 override할 수 있다" do
      %AgentTool{async: async} = Bash.tool(timeout: 1)
      result = run_async(async, %{"command" => "sleep 5"}, %{})

      assert result == "Command timed out after 1 seconds"
    end
  end

  describe "async / 출력 truncation" do
    test "짧은 출력은 그대로 반환된다 (notice 없음)" do
      %AgentTool{async: async} = Bash.tool()
      result = run_async(async, %{"command" => "echo hello"}, %{})

      refute result =~ "Showing last"
      refute result =~ "Full output:"
    end

    test "200줄 넘는 출력은 마지막 부분만 보내고 안내가 붙는다" do
      %AgentTool{async: async} = Bash.tool()

      result =
        run_async(
          async,
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
      %AgentTool{async: async} = Bash.tool()

      result =
        run_async(
          async,
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

  defp run_async(async, args, ctx) do
    async.(args, ctx, fn _ -> :ok end)
    |> Task.await(:infinity)
    |> result_text()
  end

  defp result_text(%Result{content: parts}) do
    parts
    |> Enum.flat_map(fn
      {:text, text} -> [text]
      _part -> []
    end)
    |> Enum.join()
  end

  defp tmp_path(name) do
    System.tmp_dir!()
    |> Path.join("pado-bash-test-#{System.unique_integer([:positive])}-#{name}")
  end
end
