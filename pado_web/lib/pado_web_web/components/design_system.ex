defmodule PadoWebWeb.DesignSystem do
  use Phoenix.Component

  alias Pado.Agent.Session.Entry
  alias Pado.Agent.Session.{CompactionSummary, Error, ModelChange}
  alias Pado.LLM.Message
  alias Pado.LLM.Message.{Assistant, ToolResult, User}

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

  attr :entry, Entry, required: true

  def session_entry(assigns) do
    ~H"""
    <div class={chat_class(@entry)}>
      <div class="chat-header text-xs text-base-content/50">
        {entry_label(@entry)}
      </div>
      <div class={chat_bubble_class(@entry)}>
        <p class="whitespace-pre-wrap break-words">{entry_text(@entry)}</p>
      </div>
    </div>
    """
  end

  defp format_updated_at(%DateTime{} = updated_at) do
    Calendar.strftime(updated_at, "%b %d, %H:%M")
  end

  defp format_updated_at(_updated_at), do: "Unknown"

  defp chat_class(%Entry{kind: :user}), do: "chat chat-end"
  defp chat_class(%Entry{}), do: "chat chat-start"

  defp chat_bubble_class(%Entry{kind: :user}), do: "chat-bubble chat-bubble-primary"
  defp chat_bubble_class(%Entry{kind: :assistant}), do: "chat-bubble chat-bubble-neutral"
  defp chat_bubble_class(%Entry{kind: :tool_result}), do: "chat-bubble chat-bubble-secondary"
  defp chat_bubble_class(%Entry{kind: :error}), do: "chat-bubble chat-bubble-error"
  defp chat_bubble_class(%Entry{}), do: "chat-bubble"

  defp entry_label(%Entry{kind: :user}), do: "User"
  defp entry_label(%Entry{kind: :assistant}), do: "Assistant"
  defp entry_label(%Entry{kind: :tool_result, payload: %ToolResult{tool_name: name}}), do: name
  defp entry_label(%Entry{kind: :compaction_summary}), do: "Summary"
  defp entry_label(%Entry{kind: :model_change}), do: "Model"
  defp entry_label(%Entry{kind: :error}), do: "Error"

  defp entry_text(%Entry{payload: %User{} = message}), do: message_text(message)
  defp entry_text(%Entry{payload: %Assistant{} = message}), do: message_text(message)
  defp entry_text(%Entry{payload: %ToolResult{} = message}), do: message_text(message)
  defp entry_text(%Entry{payload: %CompactionSummary{} = summary}), do: summary.summary

  defp entry_text(%Entry{payload: %ModelChange{from: nil, to: to}}) do
    "Model set to #{to}."
  end

  defp entry_text(%Entry{payload: %ModelChange{from: from, to: to}}) do
    "Model changed from #{from} to #{to}."
  end

  defp entry_text(%Entry{payload: %Error{} = error}), do: error.message

  defp message_text(message) do
    case Message.text(message) do
      "" -> "No text content."
      text -> text
    end
  end
end
