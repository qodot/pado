defmodule Pado.Agent.Loop do
  alias Pado.Agent.{Event, Job, Turn}

  @type emit_fun :: (Event.t() -> any())
  @type next_decision :: :continue | :done | :max_turns

  @spec stream(Job.t()) :: Enumerable.t()
  def stream(%Job{} = _job) do
    raise "not implemented"
  end

  @doc false
  @spec next_step(Job.t()) :: next_decision()
  def next_step(%Job{turns: turns, max_turns: max}) do
    cond do
      length(turns) >= max -> :max_turns
      has_tool_calls?(List.last(turns)) -> :continue
      true -> :done
    end
  end

  defp has_tool_calls?(nil), do: false
  defp has_tool_calls?(%Turn{assistant: assistant}), do: Turn.tool_calls(assistant) != []
end
