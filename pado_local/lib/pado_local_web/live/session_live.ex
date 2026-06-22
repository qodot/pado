defmodule PadoLocalWeb.SessionLive do
  use PadoLocalWeb, :live_view

  alias Pado.Agent, as: PadoAgent
  alias Pado.Agent.Session
  alias Pado.Agent.Session.Store
  alias Pado.LLM.Credential
  alias Pado.LLM.Catalog.OpenAICodex

  @default_sessions_directory Path.expand("~/.config/pado/sessions")
  @reasoning_efforts [:none, :low, :medium, :high, :xhigh]

  @impl true
  def mount(_params, _session, socket) do
    socket =
      assign(socket,
        page_title: "Sessions",
        selected_id: nil,
        selected_session: nil,
        selected_session_error: nil,
        message: "",
        streaming_response: nil,
        streaming_tools: [],
        streaming_order: [],
        running_session_id: nil,
        sessions: [],
        sessions_error: nil,
        model_options: model_options(),
        reasoning_effort_options: @reasoning_efforts
      )

    {:ok, socket}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    selected_id = Map.get(params, "id")

    socket =
      socket
      |> assign(:selected_id, selected_id)
      |> maybe_clear_streaming_response(selected_id)
      |> maybe_clear_streaming_tools(selected_id)
      |> assign_sessions()
      |> assign_selected_session(selected_id)

    {:noreply, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <div class="grid h-full grid-cols-1 bg-base-200/55 lg:grid-cols-[18rem_minmax(0,1fr)]">
        <aside class={[
          "min-h-52 overflow-y-auto bg-base-200/85 lg:block",
          @selected_id && "hidden"
        ]}>
          <div class="flex items-center justify-between px-4 py-3">
            <h1 class="text-base font-semibold">Sessions</h1>
            <button
              type="button"
              phx-click="create_session"
              aria-label="Start session"
              class="btn btn-primary btn-square min-h-10 w-10 rounded-box shadow-none"
            >
              <.icon name="hero-plus" class="size-4" />
            </button>
          </div>

          <div :if={@sessions_error} class="p-3">
            <div class="alert alert-error items-start text-sm">
              <.icon name="hero-exclamation-triangle" class="size-4" />
              <span>Check the sessions folder and try again.</span>
            </div>
          </div>

          <nav :if={@sessions != []} class="px-3 pb-5">
            <ul class="menu w-full gap-1 p-0">
              <.session_nav_item
                :for={session <- @sessions}
                id={session.id}
                navigate={~p"/sessions/#{session.id}"}
                cwd={session.cwd}
                updated_at={session.updated_at}
                active={session.id == @selected_id}
              />
            </ul>
          </nav>

          <div
            :if={@sessions == [] and !@sessions_error}
            class="mx-3 rounded-box bg-base-100/70 p-4 text-sm text-base-content/65"
          >
            Start a session to choose a workspace folder.
          </div>
        </aside>

        <section class="min-h-0 bg-base-100">
          <div :if={@selected_id} class="flex h-full flex-col">
            <div :if={@selected_session_error} class="p-5">
              <div class="alert alert-error mx-auto max-w-4xl items-start">
                <.icon name="hero-exclamation-triangle" class="size-5" />
                <span>Open another session or check that this session file still exists.</span>
              </div>
            </div>

            <div
              :if={@selected_session && @selected_session.entries == []}
              class="flex flex-1 items-center justify-center p-6"
            >
              <div class="max-w-sm rounded-box bg-base-100 p-6 text-center">
                <div class="mx-auto flex size-11 items-center justify-center rounded-full bg-primary/10 text-primary">
                  <.icon name="hero-chat-bubble-left-right" class="size-5" />
                </div>
                <h3 class="mt-4 text-lg font-bold">Ask the first question</h3>
                <p class="mt-2 text-sm text-base-content/60">
                  Send a message to start working in this folder.
                </p>
              </div>
            </div>

            <div
              :if={@selected_session && @selected_session.entries != []}
              id="session-entry-list"
              phx-hook="SessionScroll"
              class="min-h-0 flex-1 overflow-y-auto [scrollbar-gutter:stable] px-4 py-6 sm:px-6"
            >
              <div class="mx-auto flex max-w-4xl flex-col gap-3">
                <.session_entries
                  entries={@selected_session.entries}
                  pending_user_entry_id={
                    pending_user_entry_id(
                      @selected_session,
                      @selected_id,
                      @running_session_id,
                      @streaming_order
                    )
                  }
                />
                <%= for item <- streaming_items(@streaming_order, @streaming_response, @streaming_tools) do %>
                  <.session_running_tool
                    :if={item.kind == :tool}
                    id={running_tool_id(item.tool.id)}
                    tool={item.tool}
                  />
                  <.session_streaming_entry
                    :if={item.kind == :response}
                    id={streaming_entry_id(@selected_id)}
                    text={item.response.text}
                    thinking={item.response.thinking}
                  />
                <% end %>
              </div>
            </div>

            <.chat_composer
              :if={@selected_session && !@selected_session_error}
              id={chat_composer_id(@selected_id)}
              session_id={@selected_id}
              message={@message}
              model={@selected_session.model}
              reasoning_effort={@selected_session.reasoning_effort}
              model_options={@model_options}
              reasoning_effort_options={@reasoning_effort_options}
            />
          </div>

          <div
            :if={!@selected_id}
            class="flex h-full min-h-96 items-center justify-center p-6"
          >
            <div class="max-w-sm rounded-box bg-base-100 p-6 text-center">
              <div class="mx-auto flex size-11 items-center justify-center rounded-full bg-primary/10 text-primary">
                <.icon name="hero-arrow-left-circle" class="size-5" />
              </div>
              <h2 class="mt-4 text-xl font-bold">Open a saved session</h2>
              <p class="mt-2 text-sm text-base-content/60">
                Pick a session from the list to continue its workspace thread.
              </p>
            </div>
          </div>
        </section>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def handle_event("change_message", %{"message" => message}, socket) do
    {:noreply, assign(socket, :message, message)}
  end

  def handle_event("send_message", %{"message" => message}, socket) do
    message = String.trim(message)

    cond do
      message == "" ->
        {:noreply, assign(socket, :message, "")}

      is_nil(socket.assigns.selected_session) ->
        {:noreply, socket}

      true ->
        run_agent(socket, message)
    end
  end

  def handle_event("create_session", _params, socket) do
    case cwd_picker().pick() do
      {:ok, cwd} ->
        create_session(socket, cwd)

      :cancel ->
        {:noreply, socket}

      {:error, reason} ->
        {:noreply, assign(socket, :sessions_error, reason)}
    end
  end

  def handle_event("select_model", %{"model" => model_id}, socket) do
    case {socket.assigns.selected_session, OpenAICodex.get(model_id)} do
      {%Session{provider: _current_provider, model: _current_model} = session,
       %{id: id, provider: provider}} ->
        save_selected_session(socket, %{session | provider: provider, model: id})

      {%Session{}, nil} ->
        {:noreply, assign(socket, :selected_session_error, {:unknown_model, model_id})}

      _other ->
        {:noreply, socket}
    end
  end

  def handle_event("select_reasoning_effort", %{"effort" => effort}, socket) do
    case {socket.assigns.selected_session, parse_reasoning_effort(effort)} do
      {%Session{reasoning_effort: _current_reasoning_effort} = session, {:ok, reasoning_effort}} ->
        save_selected_session(socket, %{session | reasoning_effort: reasoning_effort})

      {%Session{}, :error} ->
        {:noreply, assign(socket, :selected_session_error, {:unknown_reasoning_effort, effort})}

      _other ->
        {:noreply, socket}
    end
  end

  @impl true
  def handle_info({:agent_event, session_id, {:job_end, data}}, socket) do
    {:noreply, finish_agent_stream(socket, session_id, data)}
  end

  def handle_info({:agent_event, session_id, {:message_update, %{llm_event: llm_event}}}, socket) do
    socket =
      if active_stream?(socket, session_id) do
        append_streaming_event(socket, llm_event)
      else
        socket
      end

    {:noreply, socket}
  end

  def handle_info({:agent_event, session_id, {:tool_execution_start, data}}, socket) do
    socket =
      if active_stream?(socket, session_id) do
        append_streaming_tool(socket, data)
      else
        socket
      end

    {:noreply, socket}
  end

  def handle_info({:agent_event, session_id, {:tool_execution_update, data}}, socket) do
    socket =
      if active_stream?(socket, session_id) do
        append_streaming_tool_update(socket, data)
      else
        socket
      end

    {:noreply, socket}
  end

  def handle_info({:agent_event, _session_id, _event}, socket), do: {:noreply, socket}

  defp assign_selected_session(socket, nil) do
    assign(socket, selected_session: nil, selected_session_error: nil)
  end

  defp assign_selected_session(socket, selected_id) do
    case Store.load(session_store(), selected_id) do
      {:ok, session} ->
        assign(socket, selected_session: session, selected_session_error: nil)

      {:error, reason} ->
        assign(socket, selected_session: nil, selected_session_error: reason)
    end
  end

  defp assign_sessions(socket) do
    case Store.list(session_store()) do
      {:ok, sessions} ->
        assign(socket, sessions: sessions, sessions_error: nil)

      {:error, reason} ->
        assign(socket, sessions: [], sessions_error: reason)
    end
  end

  defp run_agent(socket, message) do
    with %Session{} = session <- socket.assigns.selected_session,
         {:ok, model} <- session_model(session),
         {:ok, credentials} <- Credential.load(model.provider),
         {:ok, agent} <-
           PadoAgent.spawn(
             model.provider,
             credentials,
             model,
             session.reasoning_effort,
             session_store(),
             router: llm_router()
           ),
         :ok <- start_agent_stream(agent, session.id, self()),
         :ok <- wait_until_subscriber_count(agent, 1),
         :ok <- PadoAgent.run(agent, session.id, message),
         {:ok, session} <- Store.load(session_store(), session.id) do
      socket =
        socket
        |> assign(:selected_session, session)
        |> assign(:message, "")
        |> assign(:streaming_response, nil)
        |> assign(:streaming_tools, [])
        |> assign(:streaming_order, [])
        |> assign(:running_session_id, session.id)
        |> assign_sessions()
        |> push_event("clear-chat-composer", %{id: chat_composer_id(session.id)})

      {:noreply, socket}
    else
      {:error, reason} ->
        {:noreply, assign(socket, :selected_session_error, reason)}

      _other ->
        {:noreply, socket}
    end
  end

  defp session_model(%Session{model: nil}), do: {:ok, OpenAICodex.default()}

  defp session_model(%Session{model: model_id}) do
    case OpenAICodex.get(model_id) do
      nil -> {:error, {:unknown_model, model_id}}
      model -> {:ok, model}
    end
  end

  defp llm_router do
    Application.get_env(:pado_local, :llm_router, Pado.LLM)
  end

  defp start_agent_stream(agent, session_id, live_view) do
    {:ok, _pid} =
      Task.start(fn ->
        agent
        |> Pado.Stream.subscribe()
        |> Enum.each(fn event -> send(live_view, {:agent_event, session_id, event}) end)
      end)

    :ok
  end

  defp wait_until_subscriber_count(agent, count),
    do: wait_until_subscriber_count(agent, count, 50)

  defp wait_until_subscriber_count(_agent, _count, 0), do: {:error, :stream_subscribe_timeout}

  defp wait_until_subscriber_count(agent, count, attempts) do
    case :sys.get_state(agent) do
      %{subscribers: subscribers} when map_size(subscribers) >= count ->
        :ok

      _state ->
        Process.sleep(10)
        wait_until_subscriber_count(agent, count, attempts - 1)
    end
  catch
    :exit, reason -> {:error, reason}
  end

  defp append_streaming_event(socket, {:thinking_delta, %{delta: delta}}) do
    append_streaming_delta(socket, :thinking, delta)
  end

  defp append_streaming_event(socket, {:text_delta, %{delta: delta}}) do
    append_streaming_delta(socket, :text, delta)
  end

  defp append_streaming_event(socket, _event), do: socket

  defp append_streaming_tool(socket, data) do
    tool = %{
      id: data.tool_call_id,
      name: data.tool_name,
      args: data.args || %{},
      turn_index: data.turn_index,
      updates: []
    }

    streaming_tools =
      socket.assigns.streaming_tools
      |> Enum.reject(&(&1.id == tool.id))
      |> Kernel.++([tool])

    socket
    |> assign(:streaming_tools, streaming_tools)
    |> append_streaming_order({:tool, tool.id})
  end

  defp append_streaming_tool_update(socket, data) do
    update = %{
      partial_result: data.partial_result,
      turn_index: data.turn_index
    }

    streaming_tools =
      Enum.map(socket.assigns.streaming_tools, fn
        %{id: id, updates: updates} = tool when id == data.tool_call_id ->
          %{tool | updates: updates ++ [update]}

        %{id: id} = tool when id == data.tool_call_id ->
          Map.put(tool, :updates, [update])

        tool ->
          tool
      end)

    assign(socket, :streaming_tools, streaming_tools)
  end

  defp append_streaming_delta(socket, field, delta) do
    response = socket.assigns.streaming_response || empty_streaming_response()

    socket
    |> assign(:streaming_response, Map.update!(response, field, &(&1 <> delta)))
    |> append_streaming_order(:response)
  end

  defp finish_agent_stream(socket, session_id, data) do
    socket =
      if socket.assigns.running_session_id == session_id do
        assign(socket,
          running_session_id: nil,
          streaming_response: nil,
          streaming_tools: [],
          streaming_order: []
        )
      else
        socket
      end

    socket =
      if socket.assigns.selected_id == session_id do
        assign_finished_session(socket, data, session_id)
      else
        socket
      end

    assign_sessions(socket)
  end

  defp assign_finished_session(socket, %{session: %Session{} = session}, _session_id) do
    assign(socket, selected_session: session, selected_session_error: nil)
  end

  defp assign_finished_session(socket, _data, session_id) do
    case Store.load(session_store(), session_id) do
      {:ok, session} -> assign(socket, selected_session: session, selected_session_error: nil)
      {:error, reason} -> assign(socket, :selected_session_error, reason)
    end
  end

  defp active_stream?(socket, session_id) do
    socket.assigns.running_session_id == session_id and socket.assigns.selected_id == session_id
  end

  defp maybe_clear_streaming_response(socket, selected_id) do
    if socket.assigns[:running_session_id] == selected_id do
      socket
    else
      assign(socket, streaming_response: nil, streaming_order: [])
    end
  end

  defp maybe_clear_streaming_tools(socket, selected_id) do
    if socket.assigns[:running_session_id] == selected_id do
      socket
    else
      assign(socket, streaming_tools: [], streaming_order: [])
    end
  end

  defp append_streaming_order(socket, item) do
    update(socket, :streaming_order, fn order ->
      if item in order, do: order, else: order ++ [item]
    end)
  end

  defp pending_user_entry_id(
         %Session{id: id, entries: entries},
         selected_id,
         running_session_id,
         []
       )
       when id == selected_id and id == running_session_id do
    entries
    |> Enum.reverse()
    |> Enum.find(&(&1.kind == :user))
    |> case do
      %{id: id} -> id
      nil -> nil
    end
  end

  defp pending_user_entry_id(_session, _selected_id, _running_session_id, _streaming_order),
    do: nil

  defp streaming_items(order, response, tools) do
    tools_by_id = Map.new(tools, &{&1.id, &1})

    Enum.flat_map(order, fn
      :response ->
        if response, do: [%{kind: :response, response: response}], else: []

      {:tool, id} ->
        case Map.fetch(tools_by_id, id) do
          {:ok, tool} -> [%{kind: :tool, tool: tool}]
          :error -> []
        end
    end)
  end

  defp empty_streaming_response do
    %{text: "", thinking: ""}
  end

  defp save_selected_session(
         socket,
         %Session{
           id: _id,
           provider: _provider,
           model: _model,
           reasoning_effort: _reasoning_effort,
           updated_at: _updated_at
         } = session,
         opts \\ []
       ) do
    session =
      if Keyword.get(opts, :touch?, true) do
        %{session | updated_at: DateTime.utc_now()}
      else
        session
      end

    case Store.save(session_store(), session) do
      :ok ->
        socket =
          socket
          |> assign(:selected_session, session)
          |> maybe_clear_message(Keyword.get(opts, :message_saved?, false))
          |> assign_sessions()

        {:noreply, socket}

      {:error, reason} ->
        {:noreply, assign(socket, :selected_session_error, reason)}
    end
  end

  defp maybe_clear_message(socket, true), do: assign(socket, :message, "")
  defp maybe_clear_message(socket, false), do: socket

  defp parse_reasoning_effort("none"), do: {:ok, :none}
  defp parse_reasoning_effort("low"), do: {:ok, :low}
  defp parse_reasoning_effort("medium"), do: {:ok, :medium}
  defp parse_reasoning_effort("high"), do: {:ok, :high}
  defp parse_reasoning_effort("xhigh"), do: {:ok, :xhigh}
  defp parse_reasoning_effort(_effort), do: :error

  defp session_store do
    {Pado.Agent.Session.JSONL, directory: sessions_directory()}
  end

  defp cwd_picker do
    Application.get_env(:pado_local, :session_cwd_picker, PadoLocal.SessionCwdPicker)
  end

  defp create_session(socket, cwd) do
    session = Session.new(new_session_id(), cwd: cwd)

    case Store.save(session_store(), session) do
      :ok ->
        {:noreply, push_patch(socket, to: ~p"/sessions/#{session.id}")}

      {:error, reason} ->
        {:noreply, assign(socket, :sessions_error, reason)}
    end
  end

  defp sessions_directory do
    Application.get_env(:pado_local, :sessions_directory, @default_sessions_directory)
  end

  defp new_session_id do
    timestamp = System.system_time(:millisecond)
    suffix = System.unique_integer([:positive, :monotonic])
    "session-#{timestamp}-#{suffix}"
  end

  defp chat_composer_id(session_id), do: "chat-composer-#{session_id}"
  defp streaming_entry_id(session_id), do: "session-streaming-entry-#{session_id}"
  defp running_tool_id(tool_call_id), do: "session-running-tool-#{tool_call_id}"

  defp model_options do
    OpenAICodex.all()
    |> Enum.sort_by(& &1.id, :desc)
  end
end
