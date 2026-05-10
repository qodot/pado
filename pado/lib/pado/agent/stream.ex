defmodule Pado.Agent.Stream do
  alias Pado.Agent.Event

  @spec build(map()) :: Enumerable.t()
  def build(subscription) when is_map(subscription) do
    Stream.resource(
      fn -> subscription end,
      &receive_event/1,
      &cleanup_subscription/1
    )
  end

  defp receive_event(%{halted: true} = state), do: {:halt, state}

  defp receive_event(%{subscription_ref: subscription_ref, agent_monitor: agent_monitor} = state) do
    receive do
      {^subscription_ref, event} ->
        if Event.terminal?(event) do
          {[event], %{state | halted: true}}
        else
          {[event], state}
        end

      {:DOWN, ^agent_monitor, :process, _, reason} ->
        {[agent_down_event(reason)], %{state | halted: true}}
    end
  end

  defp cleanup_subscription(%{agent: agent, agent_monitor: agent_monitor, subscription_ref: ref}) do
    GenServer.cast(agent, {:unsubscribe, ref})
    Process.demonitor(agent_monitor, [:flush])
    :ok
  end

  defp agent_down_event(reason) do
    {:job_end, %{job_id: nil, status: :error, reason: reason, turns: []}}
  end
end
