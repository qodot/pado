defmodule PadoWebWeb.SessionLive do
  use PadoWebWeb, :live_view

  alias Pado.Agent.Session.Store

  @default_sessions_directory Path.expand("~/.config/pado/sessions")

  @impl true
  def mount(_params, _session, socket) do
    socket =
      assign(socket,
        page_title: "Sessions",
        selected_id: nil,
        selected_session: nil,
        selected_session_error: nil,
        sessions: [],
        sessions_error: nil
      )

    {:ok, socket}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    selected_id = Map.get(params, "id")

    socket =
      socket
      |> assign(:selected_id, selected_id)
      |> assign_sessions()
      |> assign_selected_session(selected_id)

    {:noreply, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <div class="grid h-full grid-cols-1 lg:grid-cols-[20rem_minmax(0,1fr)]">
        <aside class="min-h-52 overflow-y-auto bg-base-200/80">
          <div class="flex items-center justify-between px-5 py-5">
            <div>
              <p class="text-xs font-medium uppercase text-base-content/60">Workspace</p>
              <h1 class="text-lg font-semibold">Sessions</h1>
            </div>
            <span class="badge badge-neutral">{length(@sessions)}</span>
          </div>

          <div :if={@sessions_error} class="p-3">
            <div class="alert alert-error text-sm">
              <.icon name="hero-exclamation-triangle" class="size-4" />
              <span>Could not load sessions.</span>
            </div>
          </div>

          <nav :if={@sessions != []} class="px-3 pb-5">
            <ul class="menu w-full gap-1 p-0">
              <.session_nav_item
                :for={session <- @sessions}
                id={session.id}
                navigate={~p"/sessions/#{session.id}"}
                updated_at={session.updated_at}
                active={session.id == @selected_id}
              />
            </ul>
          </nav>

          <div :if={@sessions == [] and !@sessions_error} class="p-4 text-sm text-base-content/60">
            No sessions yet.
          </div>
        </aside>

        <section class="min-h-0 bg-base-100">
          <div :if={@selected_id} class="flex h-full flex-col">
            <div class="px-6 py-5">
              <div class="flex items-center gap-2">
                <span class="status status-success" />
                <p class="text-sm font-medium text-base-content/60">Active session</p>
              </div>
              <h2 class="mt-1 truncate text-xl font-semibold">{@selected_id}</h2>
            </div>

            <div :if={@selected_session_error} class="p-5">
              <div class="alert alert-error">
                <.icon name="hero-exclamation-triangle" class="size-5" />
                <span>Could not load session.</span>
              </div>
            </div>

            <div
              :if={@selected_session && @selected_session.entries == []}
              class="flex flex-1 items-center justify-center p-6"
            >
              <div class="max-w-sm text-center">
                <h3 class="text-lg font-semibold">No messages yet</h3>
                <p class="mt-2 text-sm text-base-content/60">
                  This session does not have any saved messages.
                </p>
              </div>
            </div>

            <div
              :if={@selected_session && @selected_session.entries != []}
              class="min-h-0 flex-1 overflow-y-auto px-6 pb-8 pt-2"
            >
              <div class="mx-auto flex max-w-3xl flex-col gap-4">
                <.session_entry :for={entry <- @selected_session.entries} entry={entry} />
              </div>
            </div>
          </div>

          <div
            :if={!@selected_id}
            class="flex h-full min-h-96 items-center justify-center p-6"
          >
            <div class="max-w-sm text-center">
              <div class="loading loading-ring loading-lg text-primary" />
              <h2 class="mt-4 text-xl font-semibold">Select a session</h2>
              <p class="mt-2 text-sm text-base-content/60">
                Choose a session from the sidebar to open its conversation.
              </p>
            </div>
          </div>
        </section>
      </div>
    </Layouts.app>
    """
  end

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

  defp session_store do
    {Pado.Agent.Session.JSONL, directory: sessions_directory()}
  end

  defp sessions_directory do
    Application.get_env(:pado_web, :sessions_directory, @default_sessions_directory)
  end
end
