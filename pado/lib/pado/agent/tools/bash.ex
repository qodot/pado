defmodule Pado.Agent.Tools.Bash do
  alias Pado.Agent.Tools.Tool, as: AgentTool
  alias Pado.LLM.Tool, as: LLMTool

  @default_timeout_seconds 60
  @max_lines 200
  @max_bytes 50_000

  @description """
  Run a bash command in the current working directory.
  Returns combined stdout and stderr together with the process exit code.
  Output is truncated to last #{@max_lines} lines or #{div(@max_bytes, 1024)}KB
  (whichever is hit first). When truncated, the full output is saved to a
  temp file and its path is included in the result so it can be inspected
  later (e.g. with `cat`, `grep`).
  Use the `timeout` argument (in seconds) to override the default for
  long-running commands. Default timeout is #{@default_timeout_seconds} seconds.
  """

  def tool(opts \\ []) do
    timeout = Keyword.get(opts, :timeout, @default_timeout_seconds)

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
      execute: fn args, ctx -> execute(args, ctx, timeout) end
    }
  end

  defp execute(%{"command" => cmd} = args, _ctx, timeout) when is_binary(cmd) do
    timeout = Map.get(args, "timeout", timeout)
    timeout_ms = timeout * 1000

    task = Task.async(fn -> System.shell(cmd, stderr_to_stdout: true) end)

    case Task.yield(task, timeout_ms) || Task.shutdown(task, :brutal_kill) do
      {:ok, {output, exit_code}} ->
        format_result(output, exit_code)

      nil ->
        "Command timed out after #{timeout} seconds"
    end
  end

  defp format_result(output, exit_code) do
    case truncate(output) do
      :ok ->
        "exit_code: #{exit_code}\n#{output}"

      {:truncated, shown, total_lines, total_bytes} ->
        path = write_temp_file(output)
        shown_lines = shown |> String.split("\n") |> length()

        notice =
          "[Showing last #{shown_lines} of #{total_lines} lines " <>
            "(#{format_size(total_bytes)} total). Full output: #{path}]"

        "exit_code: #{exit_code}\n#{shown}\n\n#{notice}"
    end
  end

  defp truncate(output) do
    lines = String.split(output, "\n")
    total_lines = length(lines)
    total_bytes = byte_size(output)

    if total_lines <= @max_lines and total_bytes <= @max_bytes do
      :ok
    else
      tail = Enum.take(lines, -min(total_lines, @max_lines))
      shown = Enum.join(tail, "\n")
      shown = clamp_bytes(shown, @max_bytes)
      {:truncated, shown, total_lines, total_bytes}
    end
  end

  defp clamp_bytes(text, limit) when byte_size(text) <= limit, do: text

  defp clamp_bytes(text, limit) do
    start = byte_size(text) - limit
    text |> binary_part(start, limit) |> String.replace_invalid()
  end

  defp write_temp_file(output) do
    hex = :crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower)
    path = Path.join(System.tmp_dir!(), "pado-bash-#{hex}.log")
    File.write!(path, output)
    path
  end

  defp format_size(bytes) when bytes < 1024, do: "#{bytes}B"

  defp format_size(bytes) when bytes < 1024 * 1024,
    do: "#{Float.round(bytes / 1024, 1)}KB"

  defp format_size(bytes),
    do: "#{Float.round(bytes / 1024 / 1024, 1)}MB"
end
