defmodule Pado.LLM.EventTest do
  use ExUnit.Case, async: true

  alias Pado.LLM.Event
  alias Pado.LLM.Message.Assistant
  alias Pado.LLM.Usage

  test "terminal?/1은 done과 error 이벤트만 종료로 본다" do
    assistant = %Assistant{}

    assert Event.terminal?({:done, %{message: assistant}})
    assert Event.terminal?({:error, %{message: assistant}})
    refute Event.terminal?({:text_delta, %{index: 0, delta: "안녕"}})
  end

  test "final_message/1은 종료 이벤트에서 최종 assistant 메시지를 꺼낸다" do
    assistant = %Assistant{content: [{:text, "완료"}], usage: Usage.empty()}

    assert Event.final_message({:done, %{message: assistant}}) == assistant
    assert Event.final_message({:error, %{message: assistant}}) == assistant
    assert Event.final_message({:text_start, %{index: 0}}) == nil
  end
end
