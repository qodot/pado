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

  @doc false
  @spec run_loop(Job.t(), emit_fun) :: {Job.t(), Event.status(), term() | nil}
  def run_loop(%Job{} = job, emit) do
    index = length(job.turns) + 1
    emit.({:turn_start, %{job_id: job.job_id, turn_index: index}})

    case Turn.take(job, emit) do
      {:ok, job} ->
        emit.({:turn_end, %{job_id: job.job_id, turn: List.last(job.turns)}})

        case next_step(job) do
          :continue -> run_loop(job, emit)
          status -> {job, status, nil}
        end

      {:error, %Job{} = job} ->
        emit.({:turn_end, %{job_id: job.job_id, turn: List.last(job.turns)}})
        reason = List.last(job.turns).assistant.error_message
        {job, :error, reason}

      {:error, reason} ->
        {job, :error, reason}
    end
  end
end
