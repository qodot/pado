defmodule Pado.Agent.Tools.Bash do
  alias Pado.Agent.Tools.Tool, as: AgentTool
  alias Pado.LLM.Tool, as: LLMTool

  @default_timeout_seconds 60

  @description """
  Run a bash command in the current working directory.
  Returns combined stdout and stderr together with the process exit code.
  Use the `timeout` argument (in seconds) to override the default for long-running commands.
  Default timeout is #{@default_timeout_seconds} seconds.
  """

  def tool(opts \\ []) do
    default_timeout = Keyword.get(opts, :timeout, @default_timeout_seconds)

    %AgentTool{
      schema:
        LLMTool.new(
          "bash",
          @description,
          %{
            "type" => "object",
            "properties" => %{
              "command" => %{
                "type" => "string",
                "description" => "Bash command to execute."
              },
              "timeout" => %{
                "type" => "integer",
                "description" => "Timeout in seconds for the command. Optional."
              }
            },
            "required" => ["command"]
          }
        ),
      execute: fn args, ctx -> execute(args, ctx, default_timeout) end
    }
  end

  defp execute(%{"command" => cmd} = args, _ctx, default_timeout) when is_binary(cmd) do
    timeout_seconds = Map.get(args, "timeout", default_timeout)
    timeout_ms = timeout_seconds * 1000

    task = Task.async(fn -> System.shell(cmd, stderr_to_stdout: true) end)

    case Task.yield(task, timeout_ms) || Task.shutdown(task, :brutal_kill) do
      {:ok, {output, exit_code}} ->
        "exit_code: #{exit_code}\n#{output}"

      nil ->
        "Command timed out after #{timeout_seconds} seconds"
    end
  end
end
