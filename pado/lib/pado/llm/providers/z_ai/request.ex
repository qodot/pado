defmodule Pado.LLM.Providers.ZAI.Request do
  alias Pado.LLM.{Context, Model, Tool}
  alias Pado.LLM.Message.{Assistant, ToolResult, User}

  @endpoint_path "/chat/completions"

  def endpoint_url(%Model{base_url: nil}), do: raise("Model.base_url is nil")

  def endpoint_url(%Model{base_url: base_url}) do
    String.trim_trailing(base_url, "/") <> @endpoint_path
  end

  def build_body(%Model{} = model, %Context{} = ctx, _session_id, opts \\ []) do
    %{
      "model" => model.id,
      "stream" => true,
      "messages" => encode_messages(ctx)
    }
    |> maybe_put("temperature", Keyword.get(opts, :temperature))
    |> maybe_put("max_tokens", Keyword.get(opts, :max_tokens))
    |> maybe_put("tool_choice", Keyword.get(opts, :tool_choice))
    |> maybe_put("tool_stream", Keyword.get(opts, :tool_stream))
    |> maybe_put("reasoning_effort", build_reasoning_effort(opts))
    |> maybe_put("tools", encode_tools(ctx.tools))
  end

  def build_headers(api_key, session_id, opts \\ []) do
    headers =
      [
        {"authorization", "Bearer " <> api_key},
        {"accept", "text/event-stream"},
        {"content-type", "application/json"},
        {"user-agent", user_agent()},
        {"x-client-request-id", session_id}
      ]

    headers ++ Keyword.get(opts, :headers, [])
  end

  defp encode_messages(%Context{system_prompt: nil, messages: messages}),
    do: encode_messages(messages)

  defp encode_messages(%Context{system_prompt: "", messages: messages}),
    do: encode_messages(messages)

  defp encode_messages(%Context{system_prompt: system_prompt, messages: messages}) do
    [%{"role" => "system", "content" => system_prompt} | encode_messages(messages)]
  end

  defp encode_messages(messages), do: Enum.flat_map(messages, &encode_message/1)

  defp encode_message(%User{content: text}) when is_binary(text) do
    [%{"role" => "user", "content" => text}]
  end

  defp encode_message(%User{content: parts}) when is_list(parts) do
    content =
      Enum.flat_map(parts, fn
        {:text, text} ->
          [%{"type" => "text", "text" => text}]

        {:image, %{media_type: mt, data: data}} ->
          [
            %{
              "type" => "image_url",
              "image_url" => %{"url" => "data:" <> mt <> ";base64," <> data}
            }
          ]

        _ ->
          []
      end)

    if content == [], do: [], else: [%{"role" => "user", "content" => content}]
  end

  defp encode_message(%Assistant{content: blocks}) do
    texts =
      blocks
      |> Enum.flat_map(fn
        {:text, text} -> [text]
        _ -> []
      end)
      |> Enum.join()

    tool_calls =
      blocks
      |> Enum.flat_map(fn
        {:tool_call, %{id: id, name: name, args: args}} ->
          [
            %{
              "id" => id,
              "type" => "function",
              "function" => %{"name" => name, "arguments" => Jason.encode!(args)}
            }
          ]

        _ ->
          []
      end)

    message =
      %{"role" => "assistant", "content" => texts}
      |> maybe_put("tool_calls", empty_to_nil(tool_calls))

    [message]
  end

  defp encode_message(%ToolResult{tool_call_id: id, content: parts}) do
    text =
      parts
      |> Enum.flat_map(fn
        {:text, t} -> [t]
        _ -> []
      end)
      |> Enum.join()

    [%{"role" => "tool", "tool_call_id" => id, "content" => text}]
  end

  defp encode_tools(nil), do: nil
  defp encode_tools([]), do: nil

  defp encode_tools(tools) do
    Enum.map(tools, fn %Tool{} = t ->
      %{
        "type" => "function",
        "function" => %{
          "name" => t.name,
          "description" => t.description,
          "parameters" => t.parameters
        }
      }
    end)
  end

  defp build_reasoning_effort(opts) do
    case Keyword.get(opts, :reasoning_effort) do
      nil -> nil
      :none -> "none"
      :low -> "high"
      :medium -> "high"
      :high -> "high"
      :xhigh -> "max"
      "none" -> "none"
      "minimal" -> "none"
      "low" -> "high"
      "medium" -> "high"
      "high" -> "high"
      "xhigh" -> "max"
      "max" -> "max"
    end
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp empty_to_nil([]), do: nil
  defp empty_to_nil(value), do: value

  defp user_agent do
    {:ok, vsn} = :application.get_key(:pado, :vsn)
    "pado " <> List.to_string(vsn)
  end
end
