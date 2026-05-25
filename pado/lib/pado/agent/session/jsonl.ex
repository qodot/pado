defmodule Pado.Agent.Session.JSONL do
  @behaviour Pado.Agent.Session.Store

  alias Pado.Agent.Session
  alias Pado.Agent.Session.Codec
  alias Pado.Agent.Session.Summary

  @impl true
  def list(opts) when is_list(opts) do
    directory = Keyword.fetch!(opts, :directory)

    directory
    |> Path.join("*.jsonl")
    |> Path.wildcard()
    |> Enum.reduce_while({:ok, []}, fn path, {:ok, summaries} ->
      case load_summary(path) do
        {:ok, summary} -> {:cont, {:ok, [summary | summaries]}}
        {:error, reason} -> {:halt, {:error, {:invalid_session_file, path, reason}}}
      end
    end)
    |> case do
      {:ok, summaries} ->
        summaries =
          summaries
          |> Enum.sort_by(& &1.updated_at, {:desc, DateTime})

        {:ok, summaries}

      error ->
        error
    end
  end

  @impl true
  def load(session_id, opts) when is_binary(session_id) and is_list(opts) do
    session_id
    |> path(opts)
    |> load()
  end

  def load(path) when is_binary(path) do
    with {:ok, data} <- File.read(path) do
      decode(data)
    end
  end

  @impl true
  def save(%Session{} = session, opts) when is_list(opts) do
    session.id
    |> path(opts)
    |> save(session)
  end

  def save(path, %Session{} = session) when is_binary(path) do
    with :ok <- File.mkdir_p(Path.dirname(path)) do
      File.write(path, encode(session))
    end
  end

  @impl true
  def append(session_id, entries, opts) when is_binary(session_id) and is_list(entries) do
    session_id
    |> path(opts)
    |> append(entries)
  end

  def append(_path, []), do: :ok

  def append(path, entries) when is_binary(path) and is_list(entries) do
    if File.exists?(path) do
      File.write(path, encode_entries(entries), [:append])
    else
      {:error, :missing_session_file}
    end
  end

  def encode(%Session{} = session) do
    header = session |> Codec.session_to_map() |> Map.delete("entries")

    [header | Enum.map(session.entries, &Codec.entry_to_map/1)]
    |> Enum.map(&Jason.encode!/1)
    |> Enum.join("\n")
    |> Kernel.<>("\n")
  end

  defp encode_entries(entries) do
    entries
    |> Enum.map(&Codec.entry_to_map/1)
    |> Enum.map(&Jason.encode!/1)
    |> Enum.join("\n")
    |> Kernel.<>("\n")
  end

  def decode(data) when is_binary(data) do
    case String.split(data, "\n", trim: true) do
      [] ->
        {:error, :empty_session_file}

      [header_line | entry_lines] ->
        with {:ok, header_map} <- Jason.decode(header_line),
             {:ok, %Session{} = header} <- Codec.session_from_map(header_map),
             {:ok, entries} <- decode_entries(entry_lines) do
          {:ok, %{header | entries: entries}}
        end
    end
  end

  defp load_summary(path) do
    with {:ok, line} <- read_first_line(path),
         {:ok, %{"type" => "session"} = map} <- Jason.decode(line),
         {:ok, created_at} <- decode_datetime(map["created_at"]),
         {:ok, updated_at} <- decode_datetime(map["updated_at"]) do
      {:ok,
       %Summary{
         id: map["id"],
         version: map["version"] || 1,
         created_at: created_at,
         updated_at: updated_at
       }}
    else
      {:ok, map} -> {:error, {:invalid_session_header, map}}
      {:error, reason} -> {:error, reason}
    end
  end

  defp read_first_line(path) do
    path
    |> File.stream!([], :line)
    |> Enum.take(1)
    |> case do
      [line] -> {:ok, String.trim_trailing(line, "\n")}
      [] -> {:error, :empty_session_file}
    end
  rescue
    error -> {:error, Exception.message(error)}
  end

  defp decode_entries(lines) do
    lines
    |> Enum.with_index(2)
    |> Enum.reduce_while({:ok, []}, fn {line, line_no}, {:ok, entries} ->
      case decode_entry(line) do
        {:ok, entry} -> {:cont, {:ok, [entry | entries]}}
        {:error, reason} -> {:halt, {:error, {:invalid_session_entry, line_no, reason}}}
      end
    end)
    |> case do
      {:ok, entries} -> {:ok, Enum.reverse(entries)}
      error -> error
    end
  end

  defp decode_entry(line) do
    with {:ok, map} <- Jason.decode(line) do
      Codec.entry_from_map(map)
    end
  end

  defp decode_datetime(nil), do: {:ok, nil}

  defp decode_datetime(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, datetime, _offset} -> {:ok, datetime}
      {:error, reason} -> {:error, {:invalid_datetime, value, reason}}
    end
  end

  defp decode_datetime(value), do: {:error, {:invalid_datetime, value}}

  defp path(session_id, opts) do
    opts
    |> Keyword.fetch!(:directory)
    |> Path.join(session_id <> ".jsonl")
  end
end
