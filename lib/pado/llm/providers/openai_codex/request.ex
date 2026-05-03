defmodule Pado.LLM.Providers.OpenAICodex.Request do
  alias Pado.LLM.{Context, Model, Tool}
  alias Pado.LLM.Message.{Assistant, ToolResult, User}

  @endpoint_path "/codex/responses"

  def endpoint_url(%Model{base_url: nil}), do: raise("Model.base_url is nil")

  def endpoint_url(%Model{base_url: base_url}) do
    String.trim_trailing(base_url, "/") <> @endpoint_path
  end

  def build_body(%Model{} = model, %Context{} = ctx, session_id, opts \\ []) do
    %{
      "model" => model.id,
      "store" => false,
      "stream" => true,
      "instructions" => ctx.system_prompt || "",
      "input" => encode_messages(ctx.messages),
      "text" => %{"verbosity" => Keyword.get(opts, :verbosity, "medium")},
      "include" => ["reasoning.encrypted_content"],
      "prompt_cache_key" => session_id,
      "tool_choice" => Keyword.get(opts, :tool_choice, "auto"),
      "parallel_tool_calls" => Keyword.get(opts, :parallel_tool_calls, true)
    }
    |> maybe_put("temperature", Keyword.get(opts, :temperature))
    |> maybe_put("tools", encode_tools(ctx.tools))
    |> maybe_put("reasoning", build_reasoning(opts))
  end

  def build_headers(access_token, account_id, session_id, opts \\ []) do
    originator = Keyword.get(opts, :originator, "pi")

    [
      {"authorization", "Bearer " <> access_token},
      {"chatgpt-account-id", account_id},
      {"originator", originator},
      {"user-agent", user_agent()},
      {"openai-beta", "responses=experimental"},
      {"accept", "text/event-stream"},
      {"content-type", "application/json"},
      {"session_id", session_id},
      {"x-client-request-id", session_id}
    ]
  end

  defp encode_messages(messages), do: Enum.flat_map(messages, &encode_message/1)

  defp encode_message(%User{content: text}) when is_binary(text) do
    [%{"role" => "user", "content" => [%{"type" => "input_text", "text" => text}]}]
  end

  defp encode_message(%User{content: parts}) when is_list(parts) do
    content =
      Enum.flat_map(parts, fn
        {:text, text} ->
          [%{"type" => "input_text", "text" => text}]

        {:image, %{media_type: mt, data: data}} ->
          [
            %{
              "type" => "input_image",
              "detail" => "auto",
              "image_url" => "data:" <> mt <> ";base64," <> data
            }
          ]

        _ ->
          []
      end)

    if content == [], do: [], else: [%{"role" => "user", "content" => content}]
  end

  defp encode_message(%Assistant{content: blocks}) do
    Enum.flat_map(blocks, fn
      {:text, text} ->
        [
          %{
            "type" => "message",
            "role" => "assistant",
            "content" => [%{"type" => "output_text", "text" => text, "annotations" => []}],
            "status" => "completed"
          }
        ]

      {:tool_call, %{id: id, name: name, args: args}} ->
        [
          %{
            "type" => "function_call",
            "call_id" => id,
            "name" => name,
            "arguments" => Jason.encode!(args)
          }
        ]

      _ ->
        []
    end)
  end

  defp encode_message(%ToolResult{tool_call_id: id, content: parts}) do
    text =
      parts
      |> Enum.flat_map(fn
        {:text, t} -> [t]
        _ -> []
      end)
      |> Enum.join()

    [
      %{
        "type" => "function_call_output",
        "call_id" => id,
        "output" => text
      }
    ]
  end

  defp encode_tools(nil), do: nil
  defp encode_tools([]), do: nil

  defp encode_tools(tools) do
    Enum.map(tools, fn %Tool{} = t ->
      %{
        "type" => "function",
        "name" => t.name,
        "description" => t.description,
        "parameters" => t.parameters
      }
    end)
  end

  defp build_reasoning(opts) do
    case Keyword.get(opts, :reasoning_effort) do
      nil ->
        nil

      effort ->
        %{
          "effort" => Atom.to_string(effort),
          "summary" => Keyword.get(opts, :reasoning_summary, "auto")
        }
    end
  end

  defp user_agent do
    {family, _} = :os.type()
    arch = :erlang.system_info(:system_architecture) |> to_string()
    "pado (#{family}; #{arch})"
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)
end
