defmodule Pado.Agent.Stream do
  alias Pado.Agent.{Event, Job}

  @spec build(pid(), Job.t()) :: Enumerable.t()
  def build(agent, %Job{} = job) when is_pid(agent) do
    Stream.resource(
      fn -> subscribe(agent, job) end,
      &receive_event/1,
      &cleanup_subscription/1
    )
  end

  defp subscribe(agent, job) do
    subscription_ref = make_ref()
    agent_monitor = Process.monitor(agent)
    callers = [self() | Process.get(:"$callers", [])]

    try do
      case GenServer.call(agent, {:subscribe, job, self(), subscription_ref, callers}) do
        :ok ->
          %{
            agent: agent,
            agent_monitor: agent_monitor,
            subscription_ref: subscription_ref,
            halted: false,
            pending: []
          }
      end
    catch
      :exit, reason ->
        Process.demonitor(agent_monitor, [:flush])

        %{
          agent: agent,
          agent_monitor: nil,
          subscription_ref: subscription_ref,
          halted: false,
          pending: [agent_down_event(reason)]
        }
    end
  end

  defp receive_event(%{pending: [event | rest]} = state) do
    {[event], %{state | pending: rest, halted: Event.terminal?(event)}}
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

  defp cleanup_subscription(%{agent_monitor: nil}), do: :ok

  defp cleanup_subscription(%{agent: agent, agent_monitor: agent_monitor, subscription_ref: ref}) do
    GenServer.cast(agent, {:unsubscribe, ref})
    Process.demonitor(agent_monitor, [:flush])
    :ok
  end

  defp agent_down_event(reason) do
    {:job_end, %{job_id: nil, status: :error, reason: reason, turns: []}}
  end
end
