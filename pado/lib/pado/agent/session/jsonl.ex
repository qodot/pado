defmodule Pado.Agent.Session.JSONL do
  @behaviour Pado.Agent.Session.Store

  alias Pado.Agent.Session
  alias Pado.Agent.Session.Entry

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
    header = session |> Session.to_map() |> Map.delete("entries")

    [header | Enum.map(session.entries, &Entry.to_map/1)]
    |> Enum.map(&Jason.encode!/1)
    |> Enum.join("\n")
    |> Kernel.<>("\n")
  end

  defp encode_entries(entries) do
    entries
    |> Enum.map(&Entry.to_map/1)
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
             {:ok, %Session{} = header} <- Session.from_map(header_map),
             {:ok, entries} <- decode_entries(entry_lines) do
          {:ok, %{header | entries: entries}}
        end
    end
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
      Entry.from_map(map)
    end
  end

  defp path(session_id, opts) do
    opts
    |> Keyword.fetch!(:directory)
    |> Path.join(session_id <> ".jsonl")
  end
end
