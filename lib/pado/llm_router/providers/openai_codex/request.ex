defmodule Pado.LLMRouter.Providers.OpenAICodex.Request do
  @moduledoc """
  `/codex/responses` 엔드포인트에 보낼 HTTP 요청(URL·헤더·바디)을 조립한다.

  순수 함수만 담는다. 실제 송신은 상위 어댑터(`OpenAICodex`)가
  수행한다. Pi 의 `buildRequestBody` / `buildSSEHeaders` / `resolveCodexUrl`
  에 대응한다.

  지원 범위(초기):

    * User 메시지 (텍스트, 이미지)
    * Assistant 메시지 (텍스트 블록, 도구 호출)
    * ToolResult 메시지 (텍스트 결과)
    * Tool 정의 (function schema)
    * reasoning_effort 옵션

  thinking content 의 `encryptedContent` 재전송, 사용자 정의 service_tier 등
  Pi 에 있는 고급 케이스는 필요해질 때 추가한다.
  """

  alias Pado.LLMRouter.{Context, Model, Tool}
  alias Pado.LLMRouter.Message.{Assistant, ToolResult, User}

  @endpoint_path "/codex/responses"

  @doc "요청 전체에서 공유할 `:session_id`가 없으면 새로 넣는다."
  @spec ensure_session_id(keyword) :: keyword
  def ensure_session_id(opts) when is_list(opts) do
    Keyword.put_new_lazy(opts, :session_id, &generate_session_id/0)
  end

  @doc "POST 할 전체 URL."
  @spec endpoint_url(Model.t()) :: String.t()
  def endpoint_url(%Model{base_url: nil}), do: raise("Model.base_url is nil")

  def endpoint_url(%Model{base_url: base_url}) do
    String.trim_trailing(base_url, "/") <> @endpoint_path
  end

  @doc """
  요청 바디(JSON 직렬화 전 맵)를 만든다.

  옵션:

    * `:session_id` — 프롬프트 캐시 키. 없으면 자동 생성.
    * `:verbosity` — `"low" | "medium" | "high"` (기본 `"medium"`).
    * `:tool_choice` — `"auto" | "none" | %{...}` (기본 `"auto"`).
    * `:parallel_tool_calls` — boolean (기본 `true`).
    * `:temperature` — float.
    * `:reasoning_effort` — `:minimal | :low | :medium | :high | :xhigh`.
    * `:reasoning_summary` — `"auto" | "concise" | "detailed"` (기본 `"auto"`).
  """
  @spec build_body(Model.t(), Context.t(), keyword) :: map
  def build_body(%Model{} = model, %Context{} = ctx, opts \\ []) do
    %{
      "model" => model.id,
      "store" => false,
      "stream" => true,
      "instructions" => ctx.system_prompt || "",
      "input" => encode_messages(ctx.messages),
      "text" => %{"verbosity" => Keyword.get(opts, :verbosity, "medium")},
      "include" => ["reasoning.encrypted_content"],
      "prompt_cache_key" => Keyword.get_lazy(opts, :session_id, &generate_session_id/0),
      "tool_choice" => Keyword.get(opts, :tool_choice, "auto"),
      "parallel_tool_calls" => Keyword.get(opts, :parallel_tool_calls, true)
    }
    |> maybe_put("temperature", Keyword.get(opts, :temperature))
    |> maybe_put("tools", encode_tools(ctx.tools))
    |> maybe_put("reasoning", build_reasoning(opts))
  end

  @doc """
  SSE 전송용 HTTP 헤더 리스트.

  `access_token`은 JWT 그대로. `account_id`는 JWT payload 의
  `chatgpt_account_id` 값.
  """
  @spec build_headers(String.t(), String.t(), keyword) :: [{String.t(), String.t()}]
  def build_headers(access_token, account_id, opts \\ []) do
    session_id = Keyword.get_lazy(opts, :session_id, &generate_session_id/0)
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

  defp generate_session_id do
    "pado-" <> (16 |> :crypto.strong_rand_bytes() |> Base.encode16(case: :lower))
  end

  defp user_agent do
    {family, _} = :os.type()
    arch = :erlang.system_info(:system_architecture) |> to_string()
    "pado (#{family}; #{arch})"
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)
end
