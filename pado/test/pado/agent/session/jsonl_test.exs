defmodule Pado.Agent.Session.JSONLTest do
  use ExUnit.Case, async: true

  alias Pado.Agent.Session

  alias Pado.Agent.Session.{
    Codec,
    CompactionSummary,
    Entry,
    Error,
    JSONL,
    ModelChange,
    Store,
    Summary
  }

  alias Pado.LLM.Message.{Assistant, ToolResult, User}
  alias Pado.LLM.Usage

  @now ~U[2026-05-17 12:00:00Z]
  @later ~U[2026-05-17 12:01:00Z]

  describe "encode/1과 decode/1" do
    test "세션 헤더와 엔트리들을 JSONL로 왕복한다" do
      session = build_session()

      assert {:ok, ^session} = session |> JSONL.encode() |> JSONL.decode()
    end

    test "첫 줄은 세션 헤더이고 이후 줄은 엔트리다" do
      lines =
        build_session()
        |> JSONL.encode()
        |> String.split("\n", trim: true)
        |> Enum.map(&Jason.decode!/1)

      assert [%{"type" => "session", "id" => "session-1"} = header | entries] = lines
      refute Map.has_key?(header, "entries")
      assert Enum.all?(entries, &match?(%{"type" => "entry"}, &1))
    end

    test "세션 헤더에 현재 모델 설정을 저장한다" do
      [header | _entries] =
        build_session()
        |> JSONL.encode()
        |> String.split("\n", trim: true)
        |> Enum.map(&Jason.decode!/1)

      assert header["provider"] == "openai_codex"
      assert header["model"] == "gpt-5.4"
      assert header["reasoning_effort"] == "high"
      assert header["cwd"] == "/tmp/pado-workspace"
    end

    test "이전 세션 헤더는 현재 모델 설정 없이도 읽는다" do
      header =
        Session.new("session-1", timestamp: @now)
        |> Codec.session_to_map()
        |> Map.delete("entries")
        |> Map.drop(["provider", "model", "reasoning_effort"])

      data = Jason.encode!(header) <> "\n"

      assert {:ok, %Session{provider: nil, model: nil, reasoning_effort: nil}} =
               JSONL.decode(data)
    end

    test "JSON로 표현할 수 없는 error reason은 inspect 문자열로 저장한다" do
      session = %{
        build_session()
        | entries: [
            %Entry{
              id: "entry-1",
              seq: 0,
              kind: :error,
              payload: %Error{message: "failed", reason: {:timeout, 1}},
              timestamp: @now
            }
          ]
      }

      assert {:ok, decoded} = session |> JSONL.encode() |> JSONL.decode()

      assert [
               %Entry{
                 payload: %Error{message: "failed", reason: "{:timeout, 1}"}
               }
             ] = decoded.entries
    end

    test "빈 파일 내용은 에러를 반환한다" do
      assert {:error, :empty_session_file} = JSONL.decode("")
    end
  end

  describe "save/2, append/3, load/1" do
    test "지정한 파일 경로에 저장하고 다시 로드한다" do
      session = build_session()
      path = tmp_path("session.jsonl")
      on_exit(fn -> File.rm(path) end)

      assert :ok = JSONL.save(path, session)
      assert {:ok, ^session} = JSONL.load(path)
    end

    test "엔트리만 JSONL 파일 끝에 추가한다" do
      session = %{build_session() | entries: []}
      entries = build_session().entries
      path = tmp_path("append.jsonl")

      on_exit(fn -> File.rm(path) end)

      assert :ok = JSONL.save(path, session)
      assert [header_before] = path |> File.read!() |> String.split("\n", trim: true)

      assert :ok = JSONL.append(path, entries)

      assert [^header_before | entry_lines] =
               path |> File.read!() |> String.split("\n", trim: true)

      assert length(entry_lines) == length(entries)
      assert {:ok, %{session | entries: entries}} == JSONL.load(path)
    end

    test "세션 파일이 없으면 append는 에러를 반환한다" do
      path = tmp_path("missing.jsonl")

      assert {:error, :missing_session_file} = JSONL.append(path, build_session().entries)
    end

    test "Store 구현체로 세션 id와 디렉터리를 사용해 저장하고 로드한다" do
      session = build_session()
      directory = tmp_path("sessions")
      path = Path.join(directory, "session-1.jsonl")

      on_exit(fn -> File.rm_rf(directory) end)

      assert :ok = JSONL.save(session, directory: directory)
      assert File.exists?(path)
      assert {:ok, ^session} = JSONL.load("session-1", directory: directory)
    end

    test "Store dispatcher로 구현체를 교체할 수 있다" do
      full_session = build_session()
      session = %{full_session | entries: []}
      directory = tmp_path("store")
      store = {JSONL, directory: directory}

      on_exit(fn -> File.rm_rf(directory) end)

      assert :ok = Store.save(store, session)
      assert :ok = Store.append(store, session.id, full_session.entries)
      assert {:ok, ^full_session} = Store.load(store, session.id)
    end
  end

  describe "list/1" do
    test "디렉터리의 세션 파일 헤더만 읽어 summary 목록을 반환한다" do
      directory = tmp_path("list")
      old_session = %{build_session() | id: "old-session", updated_at: @now}
      new_session = %{build_session() | id: "new-session", updated_at: @later}

      on_exit(fn -> File.rm_rf(directory) end)

      assert :ok = JSONL.save(old_session, directory: directory)
      assert :ok = JSONL.save(new_session, directory: directory)

      assert {:ok,
              [
                %Summary{id: "new-session", cwd: "/tmp/pado-workspace", updated_at: @later},
                %Summary{id: "old-session", cwd: "/tmp/pado-workspace", updated_at: @now}
              ]} = JSONL.list(directory: directory)
    end

    test "Store dispatcher로 summary 목록을 조회한다" do
      directory = tmp_path("store-list")
      session = build_session()
      store = {JSONL, directory: directory}

      on_exit(fn -> File.rm_rf(directory) end)

      assert :ok = Store.save(store, session)
      assert {:ok, [%Summary{id: "session-1", cwd: "/tmp/pado-workspace"}]} = Store.list(store)
    end

    test "잘못된 세션 파일이 있으면 파일 경로와 이유를 반환한다" do
      directory = tmp_path("invalid-list")
      path = Path.join(directory, "bad.jsonl")

      on_exit(fn -> File.rm_rf(directory) end)

      assert :ok = File.mkdir_p(directory)
      assert :ok = File.write(path, "{}\n")

      assert {:error, {:invalid_session_file, ^path, {:invalid_session_header, %{}}}} =
               JSONL.list(directory: directory)
    end
  end

  defp build_session do
    "session-1"
    |> Session.new(
      cwd: "/tmp/pado-workspace",
      provider: :openai_codex,
      model: "gpt-5.4",
      reasoning_effort: :high,
      timestamp: @now
    )
    |> Map.put(
      :entries,
      [
        %Entry{
          id: "entry-1",
          seq: 0,
          kind: :user,
          payload: %User{content: "hello", timestamp: @now},
          timestamp: @now
        },
        %Entry{
          id: "entry-2",
          seq: 1,
          kind: :assistant,
          payload: %Assistant{
            content: [
              {:thinking, "checking"},
              {:text, "hi"},
              {:tool_call, %{id: "call-1", name: "echo", args: %{"text" => "hi"}}}
            ],
            stop_reason: :tool_use,
            usage: %Usage{
              input: 10,
              output: 5,
              cache_read: 1,
              cache_write: 2,
              total_tokens: 18,
              cost: %{input: 0.1, output: 0.2, cache_read: 0.01, cache_write: 0.02, total: 0.33}
            },
            provider: :openai_codex,
            model: "gpt-5.4",
            timestamp: @now
          },
          refs: %{"tool_call_ids" => ["call-1"]},
          timestamp: @now
        },
        %Entry{
          id: "entry-3",
          seq: 2,
          kind: :tool_result,
          payload: %ToolResult{
            tool_call_id: "call-1",
            tool_name: "echo",
            content: [{:text, "hi"}],
            timestamp: @now
          },
          refs: %{"tool_call_id" => "call-1"},
          timestamp: @now
        },
        %Entry{
          id: "entry-4",
          seq: 3,
          kind: :compaction_summary,
          payload: %CompactionSummary{
            summary: "이전 대화 요약",
            first_kept_seq: 2,
            tokens_before: 100
          },
          timestamp: @now
        },
        %Entry{
          id: "entry-5",
          seq: 4,
          kind: :model_change,
          payload: %ModelChange{provider: :openai_codex, from: "gpt-5.3", to: "gpt-5.4"},
          timestamp: @now
        },
        %Entry{
          id: "entry-6",
          seq: 5,
          kind: :error,
          payload: %Error{message: "failed", reason: "timeout"},
          timestamp: @now
        }
      ]
    )
  end

  defp tmp_path(name) do
    Path.join(
      System.tmp_dir!(),
      "pado-agent-session-jsonl-#{System.unique_integer([:positive])}-#{name}"
    )
  end
end
