defmodule Pado.Stream do
  @spec subscribe(pid()) :: Enumerable.t()
  def subscribe(agent) when is_pid(agent) do
    Stream.resource(
      fn -> init_stream(agent) end,
      &receive_event/1,
      &cleanup_stream/1
    )
  end

  defp init_stream(agent) do
    subscriber = self()
    stream_ref = make_ref()

    try do
      case agent |> GenServer.call({:subscribe, subscriber, stream_ref}) do
        :ok ->
          %{
            agent: agent,
            stream_ref: stream_ref,
            agent_monitor: Process.monitor(agent),
            halted: false,
            pending: []
          }
      end
    catch
      :exit, reason ->
        %{
          agent_monitor: nil,
          halted: false,
          pending: [immediate_end_event(reason)]
        }
    end
  end

  defp receive_event(%{pending: [{:job_end, _} = event | rest]} = state) do
    {[event], %{state | pending: rest, halted: true}}
  end

  defp receive_event(%{pending: [event | rest]} = state) do
    {[event], %{state | pending: rest}}
  end

  defp receive_event(%{halted: true} = state), do: {:halt, state}

  defp receive_event(%{stream_ref: stream_ref, agent_monitor: agent_monitor} = state) do
    receive do
      {^stream_ref, {:job_end, _} = event} ->
        {[event], %{state | halted: true}}

      {^stream_ref, event} ->
        {[event], state}

      {:DOWN, ^agent_monitor, :process, _, reason} ->
        {[immediate_end_event(reason)], %{state | halted: true}}
    end
  end

  defp cleanup_stream(%{agent_monitor: nil}), do: :ok

  defp cleanup_stream(%{agent: agent, agent_monitor: agent_monitor, stream_ref: stream_ref}) do
    GenServer.cast(agent, {:unsubscribe, self(), stream_ref})
    Process.demonitor(agent_monitor, [:flush])
    :ok
  end

  defp immediate_end_event(reason) do
    {:job_end, %{job_id: nil, status: :error, reason: reason, turns: []}}
  end
end
