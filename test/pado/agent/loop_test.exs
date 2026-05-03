defmodule Pado.Agent.LoopTest do
  use ExUnit.Case, async: true

  alias Pado.Agent.Loop
  alias Pado.LLMRouter.Message.Assistant
  alias Pado.LLMRouter.Usage

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

      assert {:ok, ^msg} = Loop.consume_llm_stream(events, "job-1", emit)
    end

    test ":start → :error는 {:error, message} 반환", %{emit: emit} do
      msg = %Assistant{content: [{:text, "boom"}], stop_reason: :error}

      events = [
        {:start, %{message: %Assistant{}}},
        {:error, %{reason: :error, error_message: "boom", message: msg, usage: Usage.empty()}}
      ]

      assert {:error, ^msg} = Loop.consume_llm_stream(events, "job-1", emit)
    end

    test ":start에서 :message_start emit", %{emit: emit} do
      first = %Assistant{}

      events = [
        {:start, %{message: first}},
        {:done, %{stop_reason: :stop, usage: Usage.empty(), message: %Assistant{}}}
      ]

      Loop.consume_llm_stream(events, "job-1", emit)

      assert_received {:emitted, {:message_start, %{job_id: "job-1", message: ^first}}}
    end

    test "모든 LLMRouter 이벤트가 :message_update로 중계된다", %{emit: emit} do
      events = [
        {:start, %{message: %Assistant{}}},
        {:text_delta, %{index: 0, delta: "hi"}},
        {:text_delta, %{index: 0, delta: " there"}},
        {:done, %{stop_reason: :stop, usage: Usage.empty(), message: %Assistant{}}}
      ]

      Loop.consume_llm_stream(events, "job-1", emit)

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

      Loop.consume_llm_stream(events, "job-1", emit)

      assert_received {:emitted, {:message_end, %{job_id: "job-1", message: ^final}}}
    end

    test ":error에서도 :message_end emit", %{emit: emit} do
      final = %Assistant{content: [], stop_reason: :error, error_message: "x"}

      events = [
        {:start, %{message: %Assistant{}}},
        {:error, %{reason: :error, error_message: "x", message: final, usage: Usage.empty()}}
      ]

      Loop.consume_llm_stream(events, "job-1", emit)

      assert_received {:emitted, {:message_end, %{job_id: "job-1", message: ^final}}}
    end

    test "스트림이 :done/:error 없이 끝나면 {:error, _} 반환", %{emit: emit} do
      events = [
        {:start, %{message: %Assistant{}}},
        {:text_delta, %{index: 0, delta: "incomplete"}}
      ]

      assert {:error, %Assistant{stop_reason: :error}} =
               Loop.consume_llm_stream(events, "job-1", emit)
    end
  end
end
