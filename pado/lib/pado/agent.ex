defmodule Pado.Agent do
  use GenServer

  alias Pado.Agent.{Job, Session, Turn}
  alias Pado.Agent.Session.Store
  alias Pado.AgentConfig
  alias Pado.LLM.Credential.OAuth.Credentials
  alias Pado.LLM.Message.User
  alias Pado.LLM.Model

  @type t :: pid()

  @spec spawn(
          AgentConfig.provider(),
          Credentials.t(),
          Model.t(),
          AgentConfig.reasoning_effort() | nil,
          Store.t(),
          keyword()
        ) :: {:ok, pid()}
  def spawn(
        provider,
        %Credentials{} = credentials,
        %Model{} = model,
        reasoning_effort,
        session_store,
        config_opts \\ []
      ) do
    config = AgentConfig.build(provider, credentials, model, reasoning_effort, config_opts)
    GenServer.start(__MODULE__, {config, session_store})
  end

  @spec run(pid(), String.t(), String.t()) :: :ok | {:error, term()}
  def run(agent, session_id, user_message) do
    GenServer.call(agent, {:run_job, session_id, User.new(user_message), callers()})
  end

  @impl true
  def init({%AgentConfig{} = config, session_store}) do
    state = %{
      config: config,
      session_store: session_store,
      job: nil,
      callers: nil,
      subscribers: %{},
      job_worker_pid: nil,
      job_worker_monitor: nil
    }

    {:ok, state}
  end

  @impl true
  def handle_call(
        {:run_job, session_id, %User{} = user, callers},
        _from,
        %{job: nil, session_store: store} = state
      ) do
    with {:ok, session} <- Store.load(store, session_id),
         {session, _entries} = Session.append_messages(session, [user]),
         :ok <- Store.save(store, session) do
      job = build_job(session)
      {:reply, :ok, start_job(state, job, callers)}
    else
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:run_job, _session_id, %User{}, _callers}, _from, state) do
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

  def handle_info({:receive_job_event, {:turn_end, %{turn: turn}} = event}, state) do
    {state, event} = append_turn_to_session(state, turn, event)
    notify(state, event)
    {:noreply, state}
  end

  def handle_info({:receive_job_event, {:job_end, %{job: job} = data}}, state) do
    Process.demonitor(state.job_worker_monitor, [:flush])
    data = put_final_session(data, state.session_store, job.session_id)

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

  defp start_job(state, %Job{} = job, callers) do
    notify(state, {:job_start, %{job_id: job.job_id}})
    parent = self()

    send_job_event = fn event -> send(parent, {:receive_job_event, event}) end

    {pid, ref} =
      Job.run(job, state.config, callers, send_job_event)

    %{
      state
      | job: job,
        callers: callers,
        job_worker_pid: pid,
        job_worker_monitor: ref
    }
  end

  defp build_job(%Session{} = session) do
    %Job{
      messages: Session.to_llm_messages(session),
      session_id: session.id,
      cwd: session.cwd,
      job_id: new_job_id(),
      max_turns: 10
    }
  end

  defp append_turn_to_session(
         %{job: %Job{session_id: session_id}, session_store: store} = state,
         %Turn{} = turn,
         event
       ) do
    case Store.load(store, session_id) do
      {:ok, session} ->
        messages = Turn.as_llm_messages(turn)
        {session, _entries} = Session.append_messages(session, messages)

        case Store.save(store, session) do
          :ok ->
            {%{state | job: append_turn(state.job, turn)}, event}

          {:error, reason} ->
            event = put_in(event, [Access.elem(1), :session_persist_error], reason)
            {%{state | job: append_turn(state.job, turn)}, event}
        end

      {:error, reason} ->
        event = put_in(event, [Access.elem(1), :session_persist_error], reason)
        {%{state | job: append_turn(state.job, turn)}, event}
    end
  end

  defp append_turn(%Job{} = job, %Turn{} = turn), do: %{job | turns: job.turns ++ [turn]}
  defp append_turn(job, _turn), do: job

  defp put_final_session(data, store, session_id) do
    case Store.load(store, session_id) do
      {:ok, session} -> Map.put(data, :session, session)
      {:error, _reason} -> data
    end
  end

  defp sanitize_tool_event({:tool_execution_start, data}) do
    {:tool_execution_start,
     data |> Map.delete(:tool_call) |> Map.delete(:task) |> Map.delete(:abort)}
  end

  defp callers do
    [self() | Process.get(:"$callers", [])]
  end

  defp new_job_id do
    "job-" <> Integer.to_string(System.unique_integer([:positive, :monotonic]))
  end

  defp notify(%{subscribers: subscribers}, event) do
    Enum.each(subscribers, fn {_, {subscriber, stream_ref}} ->
      send(subscriber, {stream_ref, event})
    end)
  end
end
