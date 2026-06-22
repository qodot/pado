defmodule PadoLocalWeb.Layouts do
  use PadoLocalWeb, :html

  embed_templates "layouts/*"

  attr :flash, :map, required: true

  attr :current_scope, :map, default: nil

  slot :inner_block, required: true

  def app(assigns) do
    ~H"""
    <header class="navbar bg-base-100 px-4 sm:px-6 lg:px-8">
      <div class="flex-1">
        <.link
          navigate={~p"/sessions"}
          class="btn btn-ghost shrink-0 px-2 text-lg font-semibold whitespace-nowrap"
        >
          Pado Local
        </.link>
      </div>
      <div class="flex-none">
        <ul class="flex items-center gap-2 px-1">
          <li class="hidden sm:block">
            <.link navigate={~p"/sessions"} class="btn btn-ghost">
              Sessions
            </.link>
          </li>
          <li>
            <.theme_toggle />
          </li>
        </ul>
      </div>
    </header>

    <main class="h-[calc(100vh-4.5rem)] overflow-hidden">
      <div class="h-full">
        {render_slot(@inner_block)}
      </div>
    </main>

    <.flash_group flash={@flash} />
    """
  end

  attr :flash, :map, required: true
  attr :id, :string, default: "flash-group"

  def flash_group(assigns) do
    ~H"""
    <div id={@id} aria-live="polite">
      <.flash kind={:info} flash={@flash} />
      <.flash kind={:error} flash={@flash} />

      <.flash
        id="client-error"
        kind={:error}
        title={gettext("We can't find the internet")}
        phx-disconnected={show(".phx-client-error #client-error") |> JS.remove_attribute("hidden")}
        phx-connected={hide("#client-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>

      <.flash
        id="server-error"
        kind={:error}
        title={gettext("Something went wrong!")}
        phx-disconnected={show(".phx-server-error #server-error") |> JS.remove_attribute("hidden")}
        phx-connected={hide("#server-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>
    </div>
    """
  end

  def theme_toggle(assigns) do
    ~H"""
    <div class="relative flex flex-row items-center rounded-full bg-base-200 p-1">
      <div class="absolute inset-y-1 left-1 w-11 rounded-full bg-base-100 brightness-200 transition-[left] [[data-theme=light]_&]:left-12 [[data-theme=dark]_&]:left-[5.75rem]" />

      <button
        type="button"
        aria-label="Use system theme"
        class="z-10 flex min-h-11 w-11 cursor-pointer items-center justify-center rounded-full"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="system"
      >
        <.icon name="hero-computer-desktop-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>

      <button
        type="button"
        aria-label="Use light theme"
        class="z-10 flex min-h-11 w-11 cursor-pointer items-center justify-center rounded-full"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="light"
      >
        <.icon name="hero-sun-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>

      <button
        type="button"
        aria-label="Use dark theme"
        class="z-10 flex min-h-11 w-11 cursor-pointer items-center justify-center rounded-full"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="dark"
      >
        <.icon name="hero-moon-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>
    </div>
    """
  end
end
