defmodule Pado.LLMRouter.Providers.OpenAICodex.SSE do
  @moduledoc """
  SSE(Server-Sent Events) 스트림 파서.

  `/codex/responses` 같은 SSE 엔드포인트가 내보내는 원시 바이트 청크를
  이벤트 단위로 잘라낸다. JSON 디코드는 여기서 하지 않는다(상위 어댑터 몫).

  ## 규칙 (RFC 이벤트 스트림 중 우리가 쓰는 최소 집합)

    * 이벤트 경계: 빈 줄(`\\n\\n`).
    * 필드: `event: …`, `data: …`, `id: …`. `:`으로 시작하는 줄은 주석.
    * 한 이벤트 안 여러 `data:` 줄은 개행(`\\n`)으로 이어 붙인다.
    * 인식하지 못하는 필드는 무시한다.

  ## API

    * `parse_chunk/2` — 순수 함수. 누적 버퍼 + 새 청크 → `{events, buffer}`.
    * `stream/1` — Enumerable 청크 스트림을 Enumerable 이벤트 스트림으로.
  """

  defmodule Event do
    @moduledoc "파싱된 SSE 이벤트 한 개."

    @type t :: %__MODULE__{
            event: String.t() | nil,
            data: String.t(),
            id: String.t() | nil
          }

    defstruct event: nil, data: "", id: nil
  end

  @doc """
  누적 버퍼에 새 청크를 이어붙이고, 경계(`\\n\\n`)가 온 블록만 이벤트로
  잘라낸다. 아직 경계가 오지 않은 꼬리는 반환된 buffer로 다음 호출에 이어진다.

  ## 예

      {events, buffer} = SSE.parse_chunk("", "event: foo\\ndata: bar\\n\\n")
      events == [%SSE.Event{event: "foo", data: "bar"}]
      buffer == ""
  """
  @spec parse_chunk(binary, binary) :: {[Event.t()], binary}
  def parse_chunk(buffer, chunk) when is_binary(buffer) and is_binary(chunk) do
    combined = buffer <> chunk

    case String.split(combined, "\n\n") do
      [remainder] ->
        {[], remainder}

      parts ->
        {blocks, [remainder]} = Enum.split(parts, -1)

        events =
          blocks
          |> Enum.map(&parse_block/1)
          |> Enum.reject(&is_nil/1)

        {events, remainder}
    end
  end

  @doc """
  Enumerable 청크 스트림을 Enumerable 이벤트 스트림으로 변환한다.
  내부적으로 `Stream.transform/3`으로 버퍼를 누적한다.

      Req.post!(url, into: :self)
      |> Stream.unfold(...)
      |> SSE.stream()
      |> Enum.each(&handle_event/1)
  """
  @spec stream(Enumerable.t()) :: Enumerable.t()
  def stream(chunks) do
    Stream.transform(chunks, "", fn chunk, buffer ->
      parse_chunk(buffer, chunk)
    end)
  end

  defp parse_block(block) do
    block
    |> String.split("\n")
    |> Enum.reduce(nil, fn line, acc ->
      case parse_line(line) do
        nil -> acc
        {field, value} -> put_field(acc || %Event{}, field, value)
      end
    end)
  end

  defp parse_line(":" <> _), do: nil
  defp parse_line(""), do: nil

  defp parse_line(line) do
    case String.split(line, ":", parts: 2) do
      [field, value] -> {field, trim_leading_space(value)}
      [field] -> {field, ""}
    end
  end

  defp trim_leading_space(" " <> rest), do: rest
  defp trim_leading_space(other), do: other

  defp put_field(%Event{} = ev, "event", value), do: %{ev | event: value}
  defp put_field(%Event{} = ev, "id", value), do: %{ev | id: value}

  defp put_field(%Event{data: ""} = ev, "data", value),
    do: %{ev | data: value}

  defp put_field(%Event{data: existing} = ev, "data", value),
    do: %{ev | data: existing <> "\n" <> value}

  defp put_field(%Event{} = ev, _other, _value), do: ev
end
