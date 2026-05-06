defmodule Pado.Agent do
  use GenServer

  alias Pado.Agent.{Event, Job, Turn}
  alias Pado.AgentConfig

  @type t :: pid()

  # ---------------------------------------------------------------------------
  # 공개 API
  # ---------------------------------------------------------------------------

  @spec spawn(AgentConfig.t()) :: {:ok, pid()}
  def spawn(%AgentConfig{} = config) do
    owner = self()
    callers = [owner | Process.get(:"$callers", [])]
    GenServer.start(__MODULE__, {config, owner, callers})
  end

  @spec stream(pid(), Job.t()) :: {:ok, Enumerable.t()} | {:error, :not_spawning}
  def stream(agent, %Job{} = job) when is_pid(agent) do
    worker_ref = make_ref()

    try do
      case GenServer.call(agent, {:start_job, job, self(), worker_ref}) do
        :ok -> {:ok, build_stream(agent, worker_ref)}
        {:error, _} = err -> err
      end
    catch
      :exit, _ -> {:error, :not_spawning}
    end
  end

  # ---------------------------------------------------------------------------
  # GenServer 콜백
  # ---------------------------------------------------------------------------

  @impl true
  def init({%AgentConfig{} = config, owner, callers}) do
    state = %{
      config: config,
      owner: owner,
      owner_monitor: Process.monitor(owner),
      phase: :idle,
      job: nil,
      subscriber: nil,
      worker_ref: nil,
      subscriber_monitor: nil,
      turn_task_pid: nil,
      turn_task_monitor: nil,
      callers: callers
    }

    {:ok, state}
  end

  @impl true
  def handle_call({:start_job, job, subscriber, worker_ref}, _from, %{phase: :idle} = state) do
    new_state = %{
      state
      | phase: :running,
        job: job,
        subscriber: subscriber,
        worker_ref: worker_ref,
        subscriber_monitor: Process.monitor(subscriber)
    }

    notify(new_state, {:job_start, %{job_id: job.job_id}})
    {:reply, :ok, new_state, {:continue, :run_turn}}
  end

  def handle_call({:start_job, _, _, _}, _from, state) do
    {:reply, {:error, :not_spawning}, state}
  end

  @impl true
  def handle_continue(:run_turn, state) do
    parent = self()
    send_event = make_send_event(state)
    config = state.config
    job = state.job
    callers = state.callers

    {pid, ref} =
      spawn_monitor(fn ->
        Process.put(:"$callers", callers)
        result = Turn.take(config, job, send_event)
        send(parent, {:turn_result, result})
      end)

    {:noreply, %{state | turn_task_pid: pid, turn_task_monitor: ref}}
  end

  @impl true
  def handle_info({:turn_result, {:ok, job}}, state) do
    Process.demonitor(state.turn_task_monitor, [:flush])

    new_state = %{state | job: job, turn_task_pid: nil, turn_task_monitor: nil}

    case Job.next_step(job) do
      :continue -> {:noreply, new_state, {:continue, :run_turn}}
      status -> finish(new_state, status, nil)
    end
  end

  def handle_info({:turn_result, {:error, job}}, state) do
    Process.demonitor(state.turn_task_monitor, [:flush])

    reason = List.last(job.turns).assistant.error_message

    finish(
      %{state | job: job, turn_task_pid: nil, turn_task_monitor: nil},
      :error,
      reason
    )
  end

  def handle_info({:DOWN, ref, :process, _, reason}, %{turn_task_monitor: ref} = state) do
    finish(
      %{state | turn_task_pid: nil, turn_task_monitor: nil},
      :error,
      "turn task crashed: " <> inspect(reason)
    )
  end

  def handle_info({:DOWN, ref, :process, _, _}, %{owner_monitor: ref} = state) do
    {:stop, :normal, state}
  end

  def handle_info({:DOWN, ref, :process, _, _}, %{subscriber_monitor: ref} = state) do
    {:stop, :normal, state}
  end

  def handle_info(_msg, state), do: {:noreply, state}

  # ---------------------------------------------------------------------------
  # 내부 도우미
  # ---------------------------------------------------------------------------

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

  defp notify(%{subscriber: subscriber, worker_ref: worker_ref}, event) do
    send(subscriber, {worker_ref, event})
  end

  defp make_send_event(%{subscriber: subscriber, worker_ref: worker_ref}) do
    fn event -> send(subscriber, {worker_ref, event}) end
  end

  # ---------------------------------------------------------------------------
  # Stream
  # ---------------------------------------------------------------------------

  defp build_stream(agent, worker_ref) do
    Stream.resource(
      fn -> %{worker_ref: worker_ref, monitor: Process.monitor(agent), halted: false} end,
      &receive_event/1,
      fn s ->
        Process.demonitor(s.monitor, [:flush])
        :ok
      end
    )
  end

  defp receive_event(%{halted: true} = s), do: {:halt, s}

  defp receive_event(%{worker_ref: worker_ref, monitor: mon} = s) do
    receive do
      {^worker_ref, event} ->
        if Event.terminal?(event) do
          {[event], %{s | halted: true}}
        else
          {[event], s}
        end

      {:DOWN, ^mon, :process, _, reason} ->
        event =
          {:job_end, %{job_id: nil, status: :error, reason: reason, turns: []}}

        {[event], %{s | halted: true}}
    end
  end
end
