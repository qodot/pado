defmodule Pado.Agent.Stream do
  alias Pado.Agent.Event

  @spec build(pid(), reference(), reference()) :: Enumerable.t()
  def build(agent, stream_ref, agent_monitor)
      when is_pid(agent) and is_reference(stream_ref) and is_reference(agent_monitor) do
    Stream.resource(
      fn ->
        %{
          agent: agent,
          stream_ref: stream_ref,
          agent_monitor: agent_monitor,
          halted: false
        }
      end,
      &receive_event/1,
      &cleanup_stream/1
    )
  end

  defp receive_event(%{halted: true} = state), do: {:halt, state}

  defp receive_event(%{stream_ref: stream_ref, agent_monitor: agent_monitor} = state) do
    receive do
      {^stream_ref, event} ->
        if Event.terminal?(event) do
          {[event], %{state | halted: true}}
        else
          {[event], state}
        end

      {:DOWN, ^agent_monitor, :process, _, reason} ->
        {[agent_down_event(reason)], %{state | halted: true}}
    end
  end

  defp cleanup_stream(%{agent: agent, agent_monitor: agent_monitor, stream_ref: stream_ref}) do
    GenServer.cast(agent, {:unsubscribe, stream_ref})
    Process.demonitor(agent_monitor, [:flush])
    :ok
  end

  defp agent_down_event(reason) do
    {:job_end, %{job_id: nil, status: :error, reason: reason, turns: []}}
  end
end
