defmodule Pado.LLM.Providers.ZAI.EventMapperTest do
  use ExUnit.Case, async: true

  alias Pado.LLM.Message.Assistant
  alias Pado.LLM.Providers.ZAI.EventMapper
  alias Pado.LLM.{Model, SSE}

  @model %Model{
    id: "glm-test",
    provider: :z_ai,
    cost: %{input: 1.0, output: 10.0, cache_read: 0.5, cache_write: 0.0}
  }

  test "텍스트 SSE 이벤트를 정규화된 Pado 이벤트로 변환한다" do
    events =
      [
        ev(%{"choices" => [%{"index" => 0, "delta" => %{"role" => "assistant"}}]}),
        ev(%{"choices" => [%{"index" => 0, "delta" => %{"content" => "안"}}]}),
        ev(%{"choices" => [%{"index" => 0, "delta" => %{"content" => "녕"}}]}),
        ev(%{"choices" => [%{"index" => 0, "delta" => %{}, "finish_reason" => "stop"}]}),
        ev(%{
          "choices" => [],
          "usage" => %{
            "prompt_tokens" => 10,
            "completion_tokens" => 2,
            "total_tokens" => 12,
            "prompt_tokens_details" => %{"cached_tokens" => 3}
          }
        }),
        done()
      ]
      |> EventMapper.map_stream(@model)
      |> Enum.to_list()

    assert [
             {:start, %{message: %Assistant{provider: :z_ai, model: "glm-test"}}},
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
        ev(%{
          "choices" => [
            %{
              "index" => 0,
              "delta" => %{
                "tool_calls" => [
                  %{
                    "index" => 0,
                    "id" => "call_1",
                    "type" => "function",
                    "function" => %{"name" => "read_file", "arguments" => "{\"path\":\""}
                  }
                ]
              }
            }
          ]
        }),
        ev(%{
          "choices" => [
            %{
              "index" => 0,
              "delta" => %{
                "tool_calls" => [
                  %{"index" => 0, "function" => %{"arguments" => "README.md\"}"}}
                ]
              }
            }
          ]
        }),
        ev(%{"choices" => [%{"index" => 0, "delta" => %{}, "finish_reason" => "tool_calls"}]}),
        done()
      ]
      |> EventMapper.map_stream(@model)
      |> Enum.to_list()

    assert [
             {:start, _},
             {:tool_call_start, %{index: 0, id: "call_1", name: "read_file"}},
             {:tool_call_delta, %{index: 0, delta: "{\"path\":\""}},
             {:tool_call_delta, %{index: 0, delta: "README.md\"}"}},
             {:tool_call_end, %{index: 0}},
             {:done, done_payload}
           ] = events

    assert done_payload.stop_reason == :tool_use

    assert done_payload.message.content == [
             {:tool_call, %{id: "call_1", name: "read_file", args: %{"path" => "README.md"}}}
           ]
  end

  test "여러 도구 호출 인자를 index별로 누적한다" do
    events =
      [
        ev(%{
          "choices" => [
            %{
              "index" => 0,
              "delta" => %{
                "tool_calls" => [
                  %{
                    "index" => 0,
                    "id" => "call_1",
                    "function" => %{"name" => "read_file", "arguments" => "{\"path\":\"README"}
                  },
                  %{
                    "index" => 1,
                    "id" => "call_2",
                    "function" => %{"name" => "grep", "arguments" => "{\"pattern\":\"Pado"}
                  }
                ]
              }
            }
          ]
        }),
        ev(%{
          "choices" => [
            %{
              "index" => 0,
              "delta" => %{
                "tool_calls" => [
                  %{"index" => 0, "function" => %{"arguments" => ".md\"}"}},
                  %{"index" => 1, "function" => %{"arguments" => "\"}"}}
                ]
              }
            }
          ]
        }),
        ev(%{"choices" => [%{"index" => 0, "delta" => %{}, "finish_reason" => "tool_calls"}]}),
        done()
      ]
      |> EventMapper.map_stream(@model)
      |> Enum.to_list()

    assert {:done, done_payload} = List.last(events)

    assert done_payload.message.content == [
             {:tool_call, %{id: "call_1", name: "read_file", args: %{"path" => "README.md"}}},
             {:tool_call, %{id: "call_2", name: "grep", args: %{"pattern" => "Pado"}}}
           ]
  end

  test "reasoning_content SSE 이벤트를 thinking 블록으로 누적한다" do
    events =
      [
        ev(%{"choices" => [%{"index" => 0, "delta" => %{"reasoning_content" => "생"}}]}),
        ev(%{"choices" => [%{"index" => 0, "delta" => %{"reasoning_content" => "각"}}]}),
        ev(%{"choices" => [%{"index" => 0, "delta" => %{"content" => "답"}}]}),
        ev(%{"choices" => [%{"index" => 0, "delta" => %{}, "finish_reason" => "stop"}]}),
        done()
      ]
      |> EventMapper.map_stream(@model)
      |> Enum.to_list()

    assert [
             {:start, _},
             {:thinking_start, %{index: 0}},
             {:thinking_delta, %{index: 0, delta: "생"}},
             {:thinking_delta, %{index: 0, delta: "각"}},
             {:thinking_end, %{index: 0}},
             {:text_start, %{index: 0}},
             {:text_delta, %{index: 0, delta: "답"}},
             {:text_end, %{index: 0}},
             {:done, done_payload}
           ] = events

    assert done_payload.message.content == [{:thinking, "생각"}, {:text, "답"}]
  end

  test "오류 SSE 이벤트를 종료 error 이벤트로 변환한다" do
    assert [{:error, payload}] =
             [
               %SSE.Event{
                 data: Jason.encode!(%{"error" => %{"message" => "invalid api key"}})
               }
             ]
             |> EventMapper.map_stream(@model)
             |> Enum.to_list()

    assert payload.reason == :error
    assert payload.error_message == "invalid api key"
    assert payload.message.stop_reason == :error
    assert payload.message.error_message == "invalid api key"
  end

  defp ev(map), do: %SSE.Event{data: Jason.encode!(map)}
  defp done, do: %SSE.Event{data: "[DONE]"}
end
