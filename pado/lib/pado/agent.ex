defmodule Pado.Agent do
  use GenServer

  alias Pado.Agent.Job
  alias Pado.AgentConfig

  @type t :: pid()

  @spec spawn(AgentConfig.t()) :: {:ok, pid()}
  def spawn(%AgentConfig{} = config) do
    GenServer.start(__MODULE__, config)
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
  def handle_call({:start_job, _subscriber, %Job{} = job, callers}, _from, %{job: nil} = state) do
    notify(state, {:job_start, %{job_id: job.job_id}})
    parent = self()

    send_job_event = fn event -> send(parent, {:receive_job_event, event}) end

    {pid, ref} =
      Job.run(job, state.config, callers, send_job_event)

    {:reply, :ok,
     %{
       state
       | job: job,
         callers: callers,
         job_worker_pid: pid,
         job_worker_monitor: ref
     }}
  end

  def handle_call({:start_job, _subscriber, %Job{}, _callers}, _from, state) do
    {:reply, {:error, :already_started}, state}
  end

  def handle_call({:subscribe, subscriber, stream_ref}, _from, state) do
    subscriber_monitor = Process.monitor(subscriber)

    state = %{
      state
      | subscribers: state.subscribers |> Map.put(subscriber_monitor, {subscriber, stream_ref})
    }

    {:reply, :ok, state}
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

  def handle_cast(
        :abort_job,
        %{job: %Job{} = job, job_worker_pid: pid, job_worker_monitor: ref} = state
      )
      when is_pid(pid) and is_reference(ref) do
    Job.abort(job, pid, ref)

    notify(state, {
      :job_end,
      %{job_id: job.job_id, status: :aborted, reason: nil, turns: job.turns}
    })

    {:stop, :normal, state}
  end

  def handle_cast(:abort_job, state), do: {:stop, :normal, state}

  @impl true
  def handle_info({:receive_job_event, {:tool_execution_start, data} = event}, state) do
    job = Job.start_tool(state.job, data.tool_call, data.task, data.abort)
    notify(%{state | job: job}, sanitize_tool_event(event))
    {:noreply, %{state | job: job}}
  end

  def handle_info({:receive_job_event, {:tool_execution_end, data} = event}, state) do
    job = Job.finish_tool(state.job, data.tool_call_id)
    notify(%{state | job: job}, event)
    {:noreply, %{state | job: job}}
  end

  def handle_info({:receive_job_event, {:job_end, %{job: job} = data}}, state) do
    Process.demonitor(state.job_worker_monitor, [:flush])

    state = %{
      state
      | job: job,
        callers: nil,
        job_worker_pid: nil,
        job_worker_monitor: nil
    }

    notify(state, {:job_end, Map.delete(data, :job)})
    {:stop, :normal, state}
  end

  def handle_info({:receive_job_event, event}, state) do
    notify(state, event)
    {:noreply, state}
  end

  def handle_info({:DOWN, ref, :process, _, :normal}, %{job_worker_monitor: ref} = state) do
    {:noreply, state}
  end

  def handle_info({:DOWN, ref, :process, _, reason}, %{job_worker_monitor: ref} = state) do
    state = %{state | job_worker_pid: nil, job_worker_monitor: nil}

    notify(
      state,
      {:job_end,
       %{
         job_id: state.job.job_id,
         status: :error,
         reason: "job worker crashed: " <> inspect(reason),
         turns: state.job.turns
       }}
    )

    {:stop, :normal, state}
  end

  def handle_info({:DOWN, ref, :process, _, _}, state) do
    if Map.has_key?(state.subscribers, ref) do
      state = %{state | subscribers: Map.delete(state.subscribers, ref)}
      stop_if_no_subscribers(state)
    else
      {:noreply, state}
    end
  end

  def handle_info(_msg, state), do: {:noreply, state}

  # ---------------------------------------------------------------------------
  # 내부 도우미
  # ---------------------------------------------------------------------------

  defp stop_if_no_subscribers(%{subscribers: subscribers} = state)
       when map_size(subscribers) == 0 do
    GenServer.cast(self(), :abort_job)
    {:noreply, state}
  end

  defp stop_if_no_subscribers(state), do: {:noreply, state}

  defp sanitize_tool_event({:tool_execution_start, data}) do
    {:tool_execution_start,
     data |> Map.delete(:tool_call) |> Map.delete(:task) |> Map.delete(:abort)}
  end

  defp notify(%{subscribers: subscribers}, event) do
    Enum.each(subscribers, fn {_, {subscriber, stream_ref}} ->
      send(subscriber, {stream_ref, event})
    end)
  end
end
