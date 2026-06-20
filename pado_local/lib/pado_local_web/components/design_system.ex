defmodule PadoLocalWeb.DesignSystem do
  use Phoenix.Component

  import PadoLocalWeb.CoreComponents, only: [icon: 1]

  alias Pado.Agent.Session.Entry
  alias Pado.Agent.Session.{CompactionSummary, Error, ModelChange}
  alias Pado.LLM.Message
  alias Pado.LLM.Message.{Assistant, ToolResult, User}

  attr :id, :string, required: true
  attr :navigate, :string, required: true
  attr :cwd, :string, required: true
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
          <span class="truncate text-xs opacity-50" title={@cwd}>{@cwd}</span>
          <span class="text-xs opacity-60">{format_updated_at(@updated_at)}</span>
        </div>
      </.link>
    </li>
    """
  end

  attr :entries, :list, required: true

  def session_entries(assigns) do
    assigns =
      assign(assigns, :tool_results_by_call_id, tool_results_by_call_id(assigns.entries))

    ~H"""
    <.session_entry
      :for={entry <- @entries}
      :if={!grouped_tool_result?(@tool_results_by_call_id, entry)}
      entry={entry}
      tool_results_by_call_id={@tool_results_by_call_id}
    />
    """
  end

  attr :entry, Entry, required: true
  attr :tool_results_by_call_id, :map, default: %{}

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
            class="alert alert-error items-start border-0 py-3 text-sm shadow-none"
          >
            <.icon name="hero-exclamation-triangle" class="mt-0.5 size-4 shrink-0" />
            <div class="min-w-0">
              <div class="font-medium">{part.title}</div>
              <div class="mt-1 break-words text-xs leading-5 opacity-80">{part.text}</div>
            </div>
          </div>
          <p
            :if={part.kind == :thinking}
            class={[
              "whitespace-pre-wrap break-words text-sm leading-7",
              "text-base-content/50"
            ]}
            phx-no-format
          >{part.text}</p>
          <div
            :if={part.kind == :text}
            data-markdown
            class="markdown-content break-words text-sm leading-7 text-base-content"
            phx-no-format
          >{markdown_html(part.text)}</div>
          <.session_running_tool
            :if={part.kind == :tool_call}
            id={tool_call_entry_id(part.tool.id)}
            tool={part.tool}
            result={Map.get(@tool_results_by_call_id, part.tool.id)}
          />
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
      <div
        id={"#{@id}-text"}
        class={[
          "markdown-content break-words text-sm leading-7 text-base-content",
          @text == "" && "hidden"
        ]}
        data-markdown
        phx-no-format
      >{markdown_html(@text)}</div>
      <div
        :if={@text == "" and @thinking == ""}
        class="loading loading-dots loading-sm text-base-content/50"
      />
    </div>
    """
  end

  attr :id, :string, required: true
  attr :tool, :map, required: true
  attr :result, :any, default: nil

  def session_running_tool(assigns) do
    ~H"""
    <div id={@id} data-tool-execution-start class="w-full py-2">
      <div class="flex w-full flex-col rounded-lg bg-base-200 text-sm text-base-content/70">
        <div class="flex w-full items-center gap-2 px-3 py-2">
          <.icon name="hero-wrench-screwdriver" class="size-4 shrink-0 text-primary" />
          <span class="shrink-0 font-medium text-base-content">Tool call</span>
          <span class="badge badge-neutral badge-sm shrink-0">{@tool.name}</span>
          <code
            :if={tool_args_summary(@tool.args) != ""}
            class="min-w-0 truncate rounded bg-base-300 px-1.5 py-0.5 text-xs text-base-content/70"
          >
            {tool_args_summary(@tool.args)}
          </code>
        </div>
        <details
          :if={@result}
          data-tool-execution-result
          class="group border-t border-base-300"
        >
          <summary class="flex cursor-pointer list-none items-center gap-2 px-3 py-2 text-xs font-medium text-base-content/55 select-none">
            <.icon
              name="hero-chevron-right"
              class="size-3 shrink-0 transition-transform group-open:rotate-90"
            />
            <span>Result</span>
          </summary>
          <div class="markdown-content break-words px-3 pb-3 text-sm leading-7 text-base-content/80">
            {markdown_html(message_text(@result))}
          </div>
        </details>
        <div
          :if={Map.get(@tool, :updates, []) != []}
          data-tool-execution-updates
          class="border-t border-base-300 px-3 py-2"
        >
          <div class="mb-1 text-xs font-medium text-base-content/55">Updates</div>
          <div class="flex flex-col gap-1">
            <div
              :for={update <- Map.get(@tool, :updates, [])}
              class="rounded bg-base-100 px-2 py-1 text-xs leading-6 text-base-content/70"
            >
              {partial_result_text(update.partial_result)}
            </div>
          </div>
        </div>
      </div>
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
            class="btn btn-primary btn-square shrink-0 rounded-full border-0 shadow-none"
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
        class="btn btn-ghost btn-sm h-8 min-h-8 rounded-full border-0 px-2 font-normal shadow-none"
      >
        <span class="truncate">{model_label(@selected)}</span>
        <.icon name="hero-chevron-down" class="size-3" />
      </button>
      <ul
        tabindex="0"
        class="dropdown-content menu z-10 mb-2 w-56 rounded-box bg-base-100 p-2 shadow-none"
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
        class="btn btn-ghost btn-sm h-8 min-h-8 rounded-full border-0 px-2 font-normal shadow-none"
      >
        <.icon name="hero-bolt" class="size-4 text-primary" />
        <span>{reasoning_effort_label(@selected)}</span>
        <.icon name="hero-chevron-down" class="size-3" />
      </button>
      <ul
        tabindex="0"
        class="dropdown-content menu z-10 mb-2 w-44 rounded-box bg-base-100 p-2 shadow-none"
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

  defp tool_results_by_call_id(entries) do
    tool_call_ids =
      entries
      |> Enum.flat_map(&entry_tool_call_ids/1)
      |> MapSet.new()

    Enum.reduce(entries, %{}, fn
      %Entry{kind: :tool_result, payload: %ToolResult{tool_call_id: id} = result}, acc
      when is_binary(id) ->
        if MapSet.member?(tool_call_ids, id), do: Map.put_new(acc, id, result), else: acc

      _entry, acc ->
        acc
    end)
  end

  defp entry_tool_call_ids(%Entry{payload: %Assistant{content: content}}) when is_list(content) do
    Enum.flat_map(content, fn
      {:tool_call, %{id: id}} when is_binary(id) -> [id]
      _part -> []
    end)
  end

  defp entry_tool_call_ids(%Entry{}), do: []

  defp grouped_tool_result?(tool_results_by_call_id, %Entry{
         kind: :tool_result,
         payload: %ToolResult{tool_call_id: id}
       }) do
    Map.has_key?(tool_results_by_call_id, id)
  end

  defp grouped_tool_result?(_tool_results_by_call_id, %Entry{}), do: false

  defp content_parts(parts, opts \\ [])

  defp content_parts(parts, opts) when is_list(parts) do
    parts
    |> Enum.flat_map(fn
      {:thinking, text} when is_binary(text) and text != "" ->
        [%{kind: :thinking, text: text}]

      {:text, text} when is_binary(text) and text != "" ->
        [%{kind: :text, text: text}]

      {:tool_call, %{id: id, name: name, args: args}} ->
        [%{kind: :tool_call, tool: %{id: id, name: name, args: args || %{}}}]

      _part ->
        []
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

  defp tool_args_summary(%{"command" => command}) when is_binary(command) do
    String.slice(command, 0, 160)
  end

  defp tool_args_summary(_args), do: ""

  defp partial_result_text(result) when is_binary(result), do: result
  defp partial_result_text(result), do: inspect(result)

  defp tool_call_entry_id(tool_call_id), do: "session-entry-tool-#{tool_call_id}"

  defp markdown_html(text) when is_binary(text) do
    text
    |> Earmark.as_html!(gfm: true, breaks: true)
    |> HtmlSanitizeEx.markdown_html()
    |> Phoenix.HTML.raw()
  rescue
    _error -> Phoenix.HTML.html_escape(text)
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
