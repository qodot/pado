defmodule Pado.LLMRouter.Providers.OpenAICodex.SSE do
  defmodule Event do
    @type t :: %__MODULE__{
            event: String.t() | nil,
            data: String.t(),
            id: String.t() | nil
          }

    defstruct event: nil, data: "", id: nil
  end

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
