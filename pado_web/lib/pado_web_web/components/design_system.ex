defmodule PadoWebWeb.DesignSystem do
  use Phoenix.Component

  attr :id, :string, required: true
  attr :navigate, :string, required: true
  attr :updated_at, :any, default: nil
  attr :active, :boolean, default: false

  def session_nav_item(assigns) do
    ~H"""
    <li>
      <.link
        navigate={@navigate}
        class={[
          "rounded-box border border-transparent",
          @active && "active border-primary/30"
        ]}
      >
        <div class="flex min-w-0 flex-1 flex-col gap-1">
          <span class="truncate font-medium">{@id}</span>
          <span class="text-xs opacity-60">{format_updated_at(@updated_at)}</span>
        </div>
      </.link>
    </li>
    """
  end

  defp format_updated_at(%DateTime{} = updated_at) do
    Calendar.strftime(updated_at, "%b %d, %H:%M")
  end

  defp format_updated_at(_updated_at), do: "Unknown"
end
