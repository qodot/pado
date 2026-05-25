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

    <div :if={@entry.kind != :user} data-entry-kind={entry_kind(@entry)} class="py-2">
      <div :if={entry_label(@entry)} class="mb-1 text-xs text-base-content/45">
        {entry_label(@entry)}
      </div>
      <div class="space-y-3">
        <div :for={part <- entry_content_parts(@entry)} data-content-kind={part.kind}>
          <div
            :if={part.kind == :error}
            class="alert alert-error items-start py-3 text-sm"
          >
            <.icon name="hero-exclamation-triangle" class="mt-0.5 size-4 shrink-0" />
            <div class="min-w-0">
              <div class="font-medium">{part.title}</div>
              <div class="mt-1 break-words text-xs leading-5 opacity-80">{part.text}</div>
            </div>
          </div>
          <p
            :if={part.kind != :error}
            class={[
              "whitespace-pre-wrap break-words text-sm leading-7",
              part.kind == :thinking && "text-base-content/50",
              part.kind == :text && "text-base-content"
            ]}
            phx-no-format
          >{part.text}</p>
        </div>
      </div>
    </div>
    """
  end

  attr :id, :string, required: true
  attr :text, :string, default: ""
  attr :thinking, :string, default: ""

  def session_streaming_entry(assigns) do
    ~H"""
    <div id={@id} data-entry-kind="assistant" data-streaming-entry class="py-2">
      <p
        id={"#{@id}-thinking"}
        class={[
          "mb-3 whitespace-pre-wrap break-words text-sm leading-7 text-base-content/50",
          @thinking == "" && "hidden"
        ]}
        phx-no-format
      >{@thinking}</p>
      <p
        id={"#{@id}-text"}
        class={[
          "whitespace-pre-wrap break-words text-sm leading-7 text-base-content",
          @text == "" && "hidden"
        ]}
        phx-no-format
      >{@text}</p>
      <div
        :if={@text == "" and @thinking == ""}
        class="loading loading-dots loading-sm text-base-content/50"
      />
    </div>
    """
  end

  attr :session_id, :string, required: true
  attr :id, :string, required: true
  attr :message, :string, default: ""
  attr :model, :string, default: nil
  attr :reasoning_effort, :atom, default: nil
  attr :model_options, :list, default: []
  attr :reasoning_effort_options, :list, default: []

  def chat_composer(assigns) do
    ~H"""
    <form
      id={@id}
      data-chat-composer
      phx-hook="ChatComposer"
      phx-submit="send_message"
      class="bg-base-200/80 px-6 py-5"
    >
      <div class="flex w-full flex-col gap-2">
        <textarea
          name="message"
          rows="1"
          placeholder={"Message #{@session_id}"}
          class="textarea textarea-ghost min-h-12 w-full resize-none bg-transparent px-0 leading-6 focus:bg-transparent focus:!outline-none focus-visible:!outline-none focus-within:!outline-none"
          phx-no-format
        >{@message}</textarea>
        <div class="flex items-center justify-between gap-3">
          <div class="flex min-w-0 flex-wrap items-center gap-1">
            <.model_selector selected={@model} options={@model_options} />
            <.reasoning_effort_selector
              selected={@reasoning_effort}
              options={@reasoning_effort_options}
            />
          </div>
          <button
            type="submit"
            aria-label="Send message"
            class="btn btn-primary btn-square shrink-0 rounded-full"
          >
            <.icon name="hero-paper-airplane" class="size-4" />
          </button>
        </div>
      </div>
    </form>
    """
  end

  attr :selected, :string, default: nil
  attr :options, :list, default: []

  defp model_selector(assigns) do
    ~H"""
    <div class="dropdown dropdown-top">
      <button
        type="button"
        tabindex="0"
        aria-label="Select model"
        class="btn btn-ghost btn-sm h-8 min-h-8 rounded-full px-2 font-normal"
      >
        <span class="truncate">{model_label(@selected)}</span>
        <.icon name="hero-chevron-down" class="size-3" />
      </button>
      <ul
        tabindex="0"
        class="dropdown-content menu z-10 mb-2 w-56 rounded-box bg-base-100 p-2 shadow"
      >
        <li :for={model <- @options}>
          <button
            type="button"
            phx-click="select_model"
            phx-value-model={model.id}
            class={[
              "justify-between",
              model.id == @selected && "active"
            ]}
          >
            <span>{model_label(model.id)}</span>
            <.icon :if={model.id == @selected} name="hero-check" class="size-4" />
          </button>
        </li>
      </ul>
    </div>
    """
  end

  attr :selected, :atom, default: nil
  attr :options, :list, default: []

  defp reasoning_effort_selector(assigns) do
    ~H"""
    <div class="dropdown dropdown-top">
      <button
        type="button"
        tabindex="0"
        aria-label="Select intelligence"
        class="btn btn-ghost btn-sm h-8 min-h-8 rounded-full px-2 font-normal"
      >
        <.icon name="hero-bolt" class="size-4 text-primary" />
        <span>{reasoning_effort_label(@selected)}</span>
        <.icon name="hero-chevron-down" class="size-3" />
      </button>
      <ul
        tabindex="0"
        class="dropdown-content menu z-10 mb-2 w-44 rounded-box bg-base-100 p-2 shadow"
      >
        <li :for={effort <- @options}>
          <button
            type="button"
            phx-click="select_reasoning_effort"
            phx-value-effort={effort}
            class={[
              "justify-between",
              effort == @selected && "active"
            ]}
          >
            <span>{reasoning_effort_label(effort)}</span>
            <.icon :if={effort == @selected} name="hero-check" class="size-4" />
          </button>
        </li>
      </ul>
    </div>
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

  defp entry_content_parts(%Entry{
         payload: %Assistant{stop_reason: :error, content: parts} = message
       }) do
    content_parts(parts, fallback: false) ++ [assistant_error_part(message)]
  end

  defp entry_content_parts(%Entry{payload: %Assistant{content: parts}}) do
    content_parts(parts)
  end

  defp entry_content_parts(%Entry{payload: %ToolResult{content: parts}}) do
    content_parts(parts)
  end

  defp entry_content_parts(%Entry{} = entry) do
    [%{kind: :text, text: entry_text(entry)}]
  end

  defp content_parts(parts, opts \\ [])

  defp content_parts(parts, opts) when is_list(parts) do
    parts
    |> Enum.flat_map(fn
      {:thinking, text} when is_binary(text) and text != "" -> [%{kind: :thinking, text: text}]
      {:text, text} when is_binary(text) and text != "" -> [%{kind: :text, text: text}]
      _part -> []
    end)
    |> case do
      [] -> content_fallback(opts)
      parts -> parts
    end
  end

  defp content_fallback(opts) do
    if Keyword.get(opts, :fallback, true) do
      [%{kind: :text, text: "No text content."}]
    else
      []
    end
  end

  defp assistant_error_part(%Assistant{error_message: message})
       when is_binary(message) and message != "" do
    %{kind: :error, title: assistant_error_title(message), text: message}
  end

  defp assistant_error_part(%Assistant{}) do
    %{
      kind: :error,
      title: "Response error",
      text: "The response ended with an error."
    }
  end

  defp assistant_error_title(message) do
    if String.contains?(String.downcase(message), "timeout") do
      "Response timed out"
    else
      "Response error"
    end
  end

  defp message_text(message) do
    case Message.text(message) do
      "" -> "No text content."
      text -> text
    end
  end

  defp model_label(nil), do: "Model"
  defp model_label("gpt-" <> label), do: String.replace(label, "-", " ")
  defp model_label(model), do: model

  defp reasoning_effort_label(nil), do: "Intelligence"
  defp reasoning_effort_label(:none), do: "None"
  defp reasoning_effort_label(:low), do: "Low"
  defp reasoning_effort_label(:medium), do: "Medium"
  defp reasoning_effort_label(:high), do: "High"
  defp reasoning_effort_label(:xhigh), do: "Very high"
end
