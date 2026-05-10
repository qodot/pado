defmodule Pado.Agent do
  use GenServer

  alias Pado.Agent.{Job, Turn}
  alias Pado.AgentConfig

  @type t :: pid()

  @spec spawn(AgentConfig.t()) :: {:ok, pid()}
  def spawn(%AgentConfig{} = config) do
    GenServer.start(__MODULE__, config)
  end

  @spec start(pid(), Job.t()) :: :ok | {:error, :not_spawning | :already_started}
  def start(agent, %Job{} = job) when is_pid(agent) do
    callers = [self() | Process.get(:"$callers", [])]

    try do
      GenServer.call(agent, {:start, job, callers})
    catch
      :exit, _reason -> {:error, :not_spawning}
    end
  end

  @impl true
  def init(%AgentConfig{} = config) do
    state = %{
      config: config,
      job: nil,
      callers: nil,
      subscribers: %{},
      job_worker_pid: nil,
      job_worker_monitor: nil
    }

    {:ok, state}
  end

  @impl true
  def handle_call({:start, %Job{} = job, callers}, _from, %{job: nil} = state) do
    state = %{state | job: job, callers: callers}
    {:reply, :ok, start_if_ready(state)}
  end

  def handle_call({:start, %Job{}, _callers}, _from, state) do
    {:reply, {:error, :already_started}, state}
  end

  def handle_call({:subscribe, subscriber, stream_ref}, _from, state) do
    subscriber_monitor = Process.monitor(subscriber)

    state = %{
      state
      | subscribers: state.subscribers |> Map.put(subscriber_monitor, {subscriber, stream_ref})
    }

    {:reply, :ok, start_if_ready(state)}
  end

  @impl true
  def handle_cast({:unsubscribe, subscriber, stream_ref}, state) do
    state =
      case Enum.find(state.subscribers, fn {_, {pid, ref}} ->
             pid == subscriber and ref == stream_ref
           end) do
        {monitor_ref, _} ->
          Process.demonitor(monitor_ref, [:flush])
          %{state | subscribers: Map.delete(state.subscribers, monitor_ref)}

        nil ->
          state
      end

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
        callers: nil,
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

  defp start_if_ready(%{job: %Job{}, job_worker_pid: nil, subscribers: subscribers} = state)
       when map_size(subscribers) > 0 do
    notify(state, {:job_start, %{job_id: state.job.job_id}})
    {pid, ref} = start_job_worker(state.config, state.job, state.callers)
    %{state | job_worker_pid: pid, job_worker_monitor: ref}
  end

  defp start_if_ready(state), do: state

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
