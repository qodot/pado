defmodule Pado.LLMRouter.Providers.OpenAICodex.SSETest do
  use ExUnit.Case, async: true

  alias Pado.LLMRouter.Providers.OpenAICodex.SSE

  test "parse_chunk/2는 완성된 SSE 블록을 이벤트로 파싱한다" do
    chunk = "event: response.created\nid: evt_1\ndata: {\"type\":\"response.created\"}\n\n"

    assert {[%SSE.Event{event: "response.created", id: "evt_1", data: data}], ""} =
             SSE.parse_chunk("", chunk)

    assert data == ~s({"type":"response.created"})
  end

  test "parse_chunk/2는 경계가 오지 않은 꼬리를 버퍼에 남긴다" do
    assert {[], buffer} = SSE.parse_chunk("", "event: response.created\ndata: ")

    assert {[%SSE.Event{event: "response.created", data: "ok"}], ""} =
             SSE.parse_chunk(buffer, "ok\n\n")
  end

  test "여러 data 줄은 개행으로 합치고 주석과 알 수 없는 필드는 무시한다" do
    chunk = ": keep-alive\nevent: multi\nid: 1\ndata: hello\ndata: world\nunknown: ignored\n\n"

    assert {[%SSE.Event{event: "multi", id: "1", data: "hello\nworld"}], ""} =
             SSE.parse_chunk("", chunk)
  end

  test "stream/1은 청크 Enumerable을 SSE 이벤트 Enumerable로 변환한다" do
    events =
      ["event: one\ndata: 1\n\n", "event: two\ndata: 2", "\n\n"]
      |> SSE.stream()
      |> Enum.to_list()

    assert events == [
             %SSE.Event{event: "one", data: "1"},
             %SSE.Event{event: "two", data: "2"}
           ]
  end
end
