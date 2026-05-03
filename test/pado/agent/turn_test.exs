defmodule Pado.Agent.TurnTest do
  use ExUnit.Case, async: true

  alias Pado.Agent.Turn
  alias Pado.LLMRouter.Message.{Assistant, ToolResult, User}
  alias Pado.LLMRouter.Usage

  describe "flatten/1" do
    test "injected, assistant, tool_results를 시간순으로 펼친다" do
      injected = [User.new("잠깐 X도 봐줘")]
      assistant = %Assistant{content: [{:text, "ok"}]}

      tool_results = [
        ToolResult.text("c1", "search", "결과 1"),
        ToolResult.text("c2", "fetch", "결과 2")
      ]

      turn = %Turn{
        index: 1,
        injected: injected,
        assistant: assistant,
        tool_results: tool_results
      }

      assert Turn.flatten(turn) == injected ++ [assistant] ++ tool_results
    end

    test "injected가 비어 있으면 assistant + tool_results만" do
      assistant = %Assistant{content: [{:text, "hi"}]}
      tr = ToolResult.text("c1", "t", "r")

      turn = %Turn{
        index: 1,
        injected: [],
        assistant: assistant,
        tool_results: [tr]
      }

      assert Turn.flatten(turn) == [assistant, tr]
    end

    test "tool_results가 비어 있으면 injected + assistant만" do
      injected = [User.new("X")]
      assistant = %Assistant{content: [{:text, "y"}]}

      turn = %Turn{
        index: 1,
        injected: injected,
        assistant: assistant,
        tool_results: []
      }

      assert Turn.flatten(turn) == injected ++ [assistant]
    end

    test "injected와 tool_results 둘 다 비어 있으면 assistant만" do
      assistant = %Assistant{content: [{:text, "only"}]}

      turn = %Turn{index: 1, assistant: assistant}

      assert Turn.flatten(turn) == [assistant]
    end
  end

  describe "consume_llm_stream/3" do
    setup do
      test_pid = self()
      emit = fn ev -> send(test_pid, {:emitted, ev}) end
      {:ok, emit: emit}
    end

    test ":start → :done 만 있는 스트림은 {:ok, message} 반환", %{emit: emit} do
      msg = %Assistant{content: [{:text, "hi"}]}

      events = [
        {:start, %{message: %Assistant{}}},
        {:done, %{stop_reason: :stop, usage: Usage.empty(), message: msg}}
      ]

      assert {:ok, ^msg} = Turn.consume_llm_stream(events, "job-1", emit)
    end

    test ":start → :error는 {:error, message} 반환", %{emit: emit} do
      msg = %Assistant{content: [{:text, "boom"}], stop_reason: :error}

      events = [
        {:start, %{message: %Assistant{}}},
        {:error, %{reason: :error, error_message: "boom", message: msg, usage: Usage.empty()}}
      ]

      assert {:error, ^msg} = Turn.consume_llm_stream(events, "job-1", emit)
    end

    test ":start에서 :message_start emit", %{emit: emit} do
      first = %Assistant{}

      events = [
        {:start, %{message: first}},
        {:done, %{stop_reason: :stop, usage: Usage.empty(), message: %Assistant{}}}
      ]

      Turn.consume_llm_stream(events, "job-1", emit)

      assert_received {:emitted, {:message_start, %{job_id: "job-1", message: ^first}}}
    end

    test "모든 LLMRouter 이벤트가 :message_update로 중계된다", %{emit: emit} do
      events = [
        {:start, %{message: %Assistant{}}},
        {:text_delta, %{index: 0, delta: "hi"}},
        {:text_delta, %{index: 0, delta: " there"}},
        {:done, %{stop_reason: :stop, usage: Usage.empty(), message: %Assistant{}}}
      ]

      Turn.consume_llm_stream(events, "job-1", emit)

      for ev <- events do
        assert_received {:emitted, {:message_update, %{job_id: "job-1", llm_event: ^ev}}}
      end
    end

    test ":done에서 :message_end emit", %{emit: emit} do
      final = %Assistant{content: [{:text, "done"}]}

      events = [
        {:start, %{message: %Assistant{}}},
        {:done, %{stop_reason: :stop, usage: Usage.empty(), message: final}}
      ]

      Turn.consume_llm_stream(events, "job-1", emit)

      assert_received {:emitted, {:message_end, %{job_id: "job-1", message: ^final}}}
    end

    test ":error에서도 :message_end emit", %{emit: emit} do
      final = %Assistant{content: [], stop_reason: :error, error_message: "x"}

      events = [
        {:start, %{message: %Assistant{}}},
        {:error, %{reason: :error, error_message: "x", message: final, usage: Usage.empty()}}
      ]

      Turn.consume_llm_stream(events, "job-1", emit)

      assert_received {:emitted, {:message_end, %{job_id: "job-1", message: ^final}}}
    end

    test "스트림이 :done/:error 없이 끝나면 {:error, _} 반환", %{emit: emit} do
      events = [
        {:start, %{message: %Assistant{}}},
        {:text_delta, %{index: 0, delta: "incomplete"}}
      ]

      assert {:error, %Assistant{stop_reason: :error}} =
               Turn.consume_llm_stream(events, "job-1", emit)
    end
  end
end
