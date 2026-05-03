defmodule Pado.Agent.Loop do
  alias Pado.Agent.{Event, Job, Turn}

  @type emit_fun :: (Event.t() -> any())
  @type next_decision :: :continue | :done | :max_turns

  @spec stream(Job.t()) :: Enumerable.t()
  def stream(%Job{} = job) do
    Stream.resource(
      fn -> start_worker(job) end,
      &pop_event/1,
      &cleanup/1
    )
  end

  defp start_worker(%Job{} = job) do
    owner = self()
    ref = make_ref()
    emit = fn ev -> send(owner, {ref, ev}) end

    worker =
      Task.async(fn ->
        emit.({:job_start, %{job_id: job.job_id}})
        {final_job, status, reason} = run_loop(job, emit)

        emit.(
          {:job_end,
           %{
             job_id: final_job.job_id,
             status: status,
             reason: reason,
             turns: final_job.turns
           }}
        )
      end)

    %{ref: ref, worker: worker, halted: false}
  end

  defp pop_event(%{halted: true} = state), do: {:halt, state}

  defp pop_event(%{ref: ref} = state) do
    receive do
      {^ref, ev} ->
        if Event.terminal?(ev) do
          {[ev], %{state | halted: true}}
        else
          {[ev], state}
        end
    end
  end

  defp cleanup(%{worker: worker}) do
    Task.shutdown(worker, :brutal_kill)
    :ok
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
