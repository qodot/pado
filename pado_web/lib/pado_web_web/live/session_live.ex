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

    {:noreply, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <div class="grid min-h-[calc(100vh-12rem)] grid-cols-1 gap-4 lg:grid-cols-[18rem_minmax(0,1fr)]">
        <aside class="rounded-box border border-base-300 bg-base-100">
          <div class="flex items-center justify-between border-b border-base-300 px-4 py-3">
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

          <nav :if={@sessions != []} class="p-2">
            <ul class="menu w-full gap-1">
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

        <section class="rounded-box border border-base-300 bg-base-100">
          <div :if={@selected_id} class="flex h-full flex-col">
            <div class="border-b border-base-300 px-5 py-4">
              <div class="flex items-center gap-2">
                <span class="status status-success" />
                <p class="text-sm font-medium text-base-content/60">Active session</p>
              </div>
              <h2 class="mt-1 truncate text-xl font-semibold">{@selected_id}</h2>
            </div>

            <div class="flex flex-1 items-center justify-center p-6">
              <div class="chat chat-start max-w-xl">
                <div class="chat-bubble chat-bubble-neutral">
                  Messages will appear here when session playback is connected.
                </div>
              </div>
            </div>
          </div>

          <div :if={!@selected_id} class="flex h-full min-h-96 items-center justify-center p-6">
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
