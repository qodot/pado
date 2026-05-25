defmodule PadoWebWeb.DesignSystem do
  use Phoenix.Component

  import PadoWebWeb.CoreComponents, only: [icon: 1]

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
          "px-2",
          @active && "font-semibold text-primary"
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
    <div :if={@entry.kind == :user} data-entry-kind="user" class="flex justify-end">
      <div class="max-w-[min(32rem,75%)] rounded-lg bg-base-200 px-3 py-2 text-sm leading-6 text-base-content">
        <p class="whitespace-pre-wrap break-words">{entry_text(@entry)}</p>
      </div>
    </div>

    <div :if={@entry.kind != :user} data-entry-kind={entry_kind(@entry)} class="max-w-3xl py-2">
      <div :if={entry_label(@entry)} class="mb-1 text-xs text-base-content/45">
        {entry_label(@entry)}
      </div>
      <p class="whitespace-pre-wrap break-words text-sm leading-7 text-base-content" phx-no-format>{entry_text(@entry)}</p>
    </div>
    """
  end

  attr :session_id, :string, required: true
  attr :message, :string, default: ""

  def chat_composer(assigns) do
    ~H"""
    <form data-chat-composer phx-submit="send_message" class="bg-base-200/80 px-6 py-5">
      <div class="flex w-full items-end gap-2">
        <textarea
          name="message"
          rows="1"
          placeholder={"Message #{@session_id}"}
          class="textarea textarea-ghost min-h-12 flex-1 resize-none bg-transparent px-0 leading-6 focus:bg-transparent focus:!outline-none focus-visible:!outline-none focus-within:!outline-none"
          phx-no-format
        >{@message}</textarea>
        <button
          type="submit"
          aria-label="Send message"
          class="btn btn-primary btn-square shrink-0 rounded-full"
        >
          <.icon name="hero-paper-airplane" class="size-4" />
        </button>
      </div>
    </form>
    """
  end

  defp format_updated_at(%DateTime{} = updated_at) do
    Calendar.strftime(updated_at, "%b %d, %H:%M")
  end

  defp format_updated_at(_updated_at), do: "Unknown"

  defp entry_kind(%Entry{kind: kind}), do: Atom.to_string(kind)

  defp entry_label(%Entry{kind: :user}), do: "User"
  defp entry_label(%Entry{kind: :assistant}), do: nil
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
