defmodule Pado.Agent do
  use GenServer

  alias Pado.Agent.{Job, Stream, Turn}
  alias Pado.AgentConfig

  @type t :: pid()

  @spec spawn(AgentConfig.t()) :: {:ok, pid()}
  def spawn(%AgentConfig{} = config) do
    GenServer.start(__MODULE__, config)
  end

  @spec stream(pid(), Job.t()) :: {:ok, Enumerable.t()} | {:error, :not_spawning}
  def stream(agent, %Job{} = job) when is_pid(agent) do
    case subscribe(agent, job) do
      {:ok, stream_ref, agent_monitor} -> {:ok, Stream.build(agent, stream_ref, agent_monitor)}
      {:error, reason} -> {:error, reason}
    end
  end

  # ---------------------------------------------------------------------------
  # GenServer 콜백
  # ---------------------------------------------------------------------------

  @impl true
  def init(%AgentConfig{} = config) do
    state = %{
      config: config,
      job: nil,
      subscribers: %{},
      job_worker_pid: nil,
      job_worker_monitor: nil
    }

    {:ok, state}
  end

  @impl true
  def handle_call(
        {:subscribe, %Job{} = job, subscriber, stream_ref, callers},
        _from,
        %{job: nil} = state
      ) do
    state = add_subscriber(state, subscriber, stream_ref)
    notify(state, {:job_start, %{job_id: job.job_id}})

    {pid, ref} = start_job_worker(state.config, job, callers)

    {:reply, :ok,
     %{
       state
       | job: job,
         job_worker_pid: pid,
         job_worker_monitor: ref
     }}
  end

  @impl true
  def handle_call({:subscribe, %Job{}, subscriber, stream_ref, _callers}, _from, state) do
    {:reply, :ok, add_subscriber(state, subscriber, stream_ref)}
  end

  @impl true
  def handle_cast({:unsubscribe, stream_ref}, state) do
    state = remove_subscriber(state, stream_ref)
    stop_if_no_subscribers(state)
  end

  @impl true
  def handle_info({:job_worker_event, event}, state) do
    notify(state, event)
    {:noreply, state}
  end

  @impl true
  def handle_info({:job_worker_result, status, reason, job}, state) do
    Process.demonitor(state.job_worker_monitor, [:flush])

    state = %{
      state
      | job: job,
        job_worker_pid: nil,
        job_worker_monitor: nil
    }

    finish(state, status, reason)
  end

  @impl true
  def handle_info({:DOWN, ref, :process, _, :normal}, %{job_worker_monitor: ref} = state) do
    {:noreply, state}
  end

  @impl true
  def handle_info({:DOWN, ref, :process, _, reason}, %{job_worker_monitor: ref} = state) do
    state = %{state | job_worker_pid: nil, job_worker_monitor: nil}
    finish(state, :error, "job worker crashed: " <> inspect(reason))
  end

  @impl true
  def handle_info({:DOWN, ref, :process, _, _}, state) do
    if Map.has_key?(state.subscribers, ref) do
      state = %{state | subscribers: Map.delete(state.subscribers, ref)}
      stop_if_no_subscribers(state)
    else
      {:noreply, state}
    end
  end

  @impl true
  def handle_info(_msg, state), do: {:noreply, state}

  # ---------------------------------------------------------------------------
  # 내부 도우미
  # ---------------------------------------------------------------------------

  defp subscribe(agent, job) do
    stream_ref = make_ref()
    agent_monitor = Process.monitor(agent)
    callers = [self() | Process.get(:"$callers", [])]

    try do
      case GenServer.call(agent, {:subscribe, job, self(), stream_ref, callers}) do
        :ok -> {:ok, stream_ref, agent_monitor}
      end
    catch
      :exit, _reason ->
        Process.demonitor(agent_monitor, [:flush])
        {:error, :not_spawning}
    end
  end

  defp start_job_worker(config, job, callers) do
    parent = self()

    spawn_monitor(fn ->
      Process.put(:"$callers", callers)

      {status, reason, job} =
        run_job(config, job, fn event ->
          send(parent, {:job_worker_event, event})
        end)

      send(parent, {:job_worker_result, status, reason, job})
    end)
  end

  defp run_job(config, job, send_event) do
    case Turn.take(config, job, send_event) do
      {:ok, job} ->
        case Job.next_step(job) do
          :continue -> run_job(config, job, send_event)
          status -> {status, nil, job}
        end

      {:error, job} ->
        reason = List.last(job.turns).assistant.error_message
        {:error, reason, job}
    end
  end

  defp add_subscriber(state, subscriber, stream_ref) do
    monitor_ref = Process.monitor(subscriber)
    subscribers = Map.put(state.subscribers, monitor_ref, {subscriber, stream_ref})
    %{state | subscribers: subscribers}
  end

  defp remove_subscriber(state, stream_ref) do
    case Enum.find(state.subscribers, fn {_, {_, ref}} -> ref == stream_ref end) do
      {monitor_ref, _} ->
        Process.demonitor(monitor_ref, [:flush])
        %{state | subscribers: Map.delete(state.subscribers, monitor_ref)}

      nil ->
        state
    end
  end

  defp stop_if_no_subscribers(%{subscribers: subscribers} = state)
       when map_size(subscribers) == 0 do
    cancel_job_worker(state)
    {:stop, :normal, state}
  end

  defp stop_if_no_subscribers(state), do: {:noreply, state}

  defp cancel_job_worker(%{job_worker_pid: nil}), do: :ok

  defp cancel_job_worker(%{job_worker_pid: pid, job_worker_monitor: monitor_ref}) do
    Process.demonitor(monitor_ref, [:flush])
    Process.exit(pid, :shutdown)
    :ok
  end

  defp finish(state, status, reason) do
    notify(
      state,
      {:job_end,
       %{
         job_id: state.job.job_id,
         status: status,
         reason: reason,
         turns: state.job.turns
       }}
    )

    {:stop, :normal, state}
  end

  defp notify(%{subscribers: subscribers}, event) do
    Enum.each(subscribers, fn {_, {subscriber, stream_ref}} ->
      send(subscriber, {stream_ref, event})
    end)
  end
end
