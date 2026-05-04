defmodule Pado.Agent.Tools.Bash do
  alias Pado.Agent.Tools.Tool, as: AgentTool
  alias Pado.LLM.Tool, as: LLMTool

  @description """
  Run a bash command in the current working directory.
  Returns combined stdout and stderr together with the process exit code.
  """

  def tool do
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
              }
            },
            "required" => ["command"]
          }
        ),
      execute: &execute/2
    }
  end

  defp execute(%{"command" => cmd}, _ctx) when is_binary(cmd) do
    {output, exit_code} = System.shell(cmd, stderr_to_stdout: true)
    "exit_code: #{exit_code}\n#{output}"
  end
end
