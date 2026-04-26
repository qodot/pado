defmodule Pado.LLMRouter.Providers.OpenAICodex.EventMapperTest do
  use ExUnit.Case, async: true

  alias Pado.LLMRouter.Message.Assistant
  alias Pado.LLMRouter.Model
  alias Pado.LLMRouter.Providers.OpenAICodex.{EventMapper, SSE}

  @model %Model{
    id: "gpt-test",
    provider: :openai_codex,
    cost: %{input: 1.0, output: 10.0, cache_read: 0.5, cache_write: 0.0}
  }

  test "텍스트 SSE 이벤트를 정규화된 Pado 이벤트로 변환한다" do
    events =
      [
        ev(%{"type" => "response.created"}),
        ev(%{
          "type" => "response.output_item.added",
          "output_index" => 0,
          "item" => %{"type" => "message"}
        }),
        ev(%{"type" => "response.output_text.delta", "output_index" => 0, "delta" => "안"}),
        ev(%{"type" => "response.output_text.delta", "output_index" => 0, "delta" => "녕"}),
        ev(%{"type" => "response.output_text.done", "output_index" => 0, "text" => "안녕"}),
        ev(%{
          "type" => "response.completed",
          "response" => %{
            "status" => "completed",
            "usage" => %{
              "input_tokens" => 10,
              "output_tokens" => 2,
              "total_tokens" => 12,
              "input_tokens_details" => %{"cached_tokens" => 3}
            }
          }
        })
      ]
      |> EventMapper.map_stream(@model)
      |> Enum.to_list()

    assert [
             {:start, %{message: %Assistant{provider: :openai_codex, model: "gpt-test"}}},
             {:text_start, %{index: 0}},
             {:text_delta, %{index: 0, delta: "안"}},
             {:text_delta, %{index: 0, delta: "녕"}},
             {:text_end, %{index: 0}},
             {:done, done_payload}
           ] = events

    assert done_payload.stop_reason == :stop
    assert done_payload.message.content == [{:text, "안녕"}]
    assert done_payload.message.stop_reason == :stop
    assert done_payload.usage.input == 7
    assert done_payload.usage.cache_read == 3
    assert done_payload.usage.output == 2
    assert done_payload.usage.total_tokens == 12
    assert done_payload.usage.cost.total > 0.0
  end

  test "도구 호출 SSE 이벤트를 tool_call 블록으로 누적하고 stop_reason을 tool_use로 둔다" do
    events =
      [
        ev(%{"type" => "response.created"}),
        ev(%{
          "type" => "response.output_item.added",
          "output_index" => 1,
          "item" => %{"type" => "function_call", "call_id" => "call_1", "name" => "read_file"}
        }),
        ev(%{
          "type" => "response.function_call_arguments.delta",
          "output_index" => 1,
          "delta" => "{\"path\":\""
        }),
        ev(%{
          "type" => "response.function_call_arguments.delta",
          "output_index" => 1,
          "delta" => "README.md\"}"
        }),
        ev(%{"type" => "response.function_call_arguments.done", "output_index" => 1}),
        ev(%{
          "type" => "response.completed",
          "response" => %{"status" => "completed", "usage" => %{"total_tokens" => 0}}
        })
      ]
      |> EventMapper.map_stream(@model)
      |> Enum.to_list()

    assert [
             {:start, _},
             {:tool_call_start, %{index: 1, id: "call_1", name: "read_file"}},
             {:tool_call_delta, %{index: 1, delta: "{\"path\":\""}},
             {:tool_call_delta, %{index: 1, delta: "README.md\"}"}},
             {:tool_call_end, %{index: 1}},
             {:done, done_payload}
           ] = events

    assert done_payload.stop_reason == :tool_use

    assert done_payload.message.content == [
             {:tool_call, %{id: "call_1", name: "read_file", args: %{"path" => "README.md"}}}
           ]
  end

  test "여러 도구 호출 인자를 output_index별로 누적한다" do
    events =
      [
        ev(%{"type" => "response.created"}),
        ev(%{
          "type" => "response.output_item.added",
          "output_index" => 0,
          "item" => %{"type" => "function_call", "call_id" => "call_1", "name" => "read_file"}
        }),
        ev(%{
          "type" => "response.output_item.added",
          "output_index" => 1,
          "item" => %{"type" => "function_call", "call_id" => "call_2", "name" => "grep"}
        }),
        ev(%{
          "type" => "response.function_call_arguments.delta",
          "output_index" => 0,
          "delta" => "{\"path\":\"README"
        }),
        ev(%{
          "type" => "response.function_call_arguments.delta",
          "output_index" => 1,
          "delta" => "{\"pattern\":\"Pado"
        }),
        ev(%{
          "type" => "response.function_call_arguments.delta",
          "output_index" => 0,
          "delta" => ".md\"}"
        }),
        ev(%{
          "type" => "response.function_call_arguments.delta",
          "output_index" => 1,
          "delta" => "\"}"
        }),
        ev(%{"type" => "response.function_call_arguments.done", "output_index" => 0}),
        ev(%{"type" => "response.function_call_arguments.done", "output_index" => 1}),
        ev(%{
          "type" => "response.completed",
          "response" => %{"status" => "completed", "usage" => %{"total_tokens" => 0}}
        })
      ]
      |> EventMapper.map_stream(@model)
      |> Enum.to_list()

    assert {:done, done_payload} = List.last(events)

    assert done_payload.message.content == [
             {:tool_call, %{id: "call_1", name: "read_file", args: %{"path" => "README.md"}}},
             {:tool_call, %{id: "call_2", name: "grep", args: %{"pattern" => "Pado"}}}
           ]
  end

  test "reasoning SSE 이벤트를 thinking 블록으로 누적한다" do
    events =
      [
        ev(%{"type" => "response.created"}),
        ev(%{
          "type" => "response.output_item.added",
          "output_index" => 0,
          "item" => %{"type" => "reasoning"}
        }),
        ev(%{
          "type" => "response.reasoning_summary_text.delta",
          "output_index" => 0,
          "delta" => "문제를 "
        }),
        ev(%{
          "type" => "response.reasoning_summary_text.delta",
          "output_index" => 0,
          "delta" => "분해합니다."
        }),
        ev(%{
          "type" => "response.reasoning_summary_text.done",
          "output_index" => 0,
          "text" => "문제를 분해합니다."
        }),
        ev(%{
          "type" => "response.completed",
          "response" => %{"status" => "completed", "usage" => %{"total_tokens" => 0}}
        })
      ]
      |> EventMapper.map_stream(@model)
      |> Enum.to_list()

    assert [
             {:start, _},
             {:thinking_start, %{index: 0}},
             {:thinking_delta, %{index: 0, delta: "문제를 "}},
             {:thinking_delta, %{index: 0, delta: "분해합니다."}},
             {:thinking_end, %{index: 0}},
             {:done, done_payload}
           ] = events

    assert done_payload.message.content == [{:thinking, "문제를 분해합니다."}]
  end

  test "오류 SSE 이벤트를 종료 error 이벤트로 변환한다" do
    assert [{:error, payload}] =
             [%SSE.Event{data: Jason.encode!(%{"type" => "error", "message" => "권한 오류"})}]
             |> EventMapper.map_stream(@model)
             |> Enum.to_list()

    assert payload.reason == :error
    assert payload.error_message == "권한 오류"
    assert payload.message.stop_reason == :error
    assert payload.message.error_message == "권한 오류"
  end

  defp ev(map), do: %SSE.Event{data: Jason.encode!(map)}
end
