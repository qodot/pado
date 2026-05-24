defmodule PadoWebWeb.SessionLiveTest do
  use PadoWebWeb.ConnCase

  alias Pado.Agent.Session
  alias Pado.Agent.Session.Store
  alias Pado.LLM.Message.{Assistant, User}

  setup do
    directory =
      System.tmp_dir!()
      |> Path.join("pado-web-session-live-#{System.unique_integer([:positive])}")

    previous = Application.get_env(:pado_web, :sessions_directory)
    Application.put_env(:pado_web, :sessions_directory, directory)

    on_exit(fn ->
      if previous do
        Application.put_env(:pado_web, :sessions_directory, previous)
      else
        Application.delete_env(:pado_web, :sessions_directory)
      end

      File.rm_rf(directory)
    end)

    %{store: {Pado.Agent.Session.JSONL, directory: directory}}
  end

  test "GET /sessions shows the session workspace", %{conn: conn} do
    conn = get(conn, ~p"/sessions")

    response = html_response(conn, 200)
    assert response =~ "Pado Web"
    assert response =~ "Sessions"
    assert response =~ "Select a session"
  end

  test "GET /sessions lists stored sessions", %{conn: conn, store: store} do
    :ok = Store.save(store, session("session-a"))
    :ok = Store.save(store, session("session-b"))

    conn = get(conn, ~p"/sessions")

    response = html_response(conn, 200)
    assert response =~ "session-a"
    assert response =~ "session-b"
    assert response =~ ~s(href="/sessions/session-a")
  end

  test "GET /sessions/:id marks the selected session", %{conn: conn, store: store} do
    :ok = Store.save(store, session("session-a"))

    conn = get(conn, ~p"/sessions/session-a")

    response = html_response(conn, 200)
    assert response =~ "Active session"
    assert response =~ "session-a"
  end

  test "GET /sessions/:id renders stored messages", %{conn: conn, store: store} do
    session =
      "session-a"
      |> session()
      |> append_messages([
        User.new("Hello from user"),
        %Assistant{content: [{:text, "Hello from assistant"}]}
      ])

    :ok = Store.save(store, session)

    conn = get(conn, ~p"/sessions/session-a")

    response = html_response(conn, 200)
    assert response =~ "Hello from user"
    assert response =~ "Hello from assistant"
    assert response =~ ~s(data-entry-kind="user")
    assert response =~ ~s(data-entry-kind="assistant")
    assert response =~ "rounded-lg"
    refute response =~ "chat-bubble"
  end

  test "GET /sessions/:id renders assistant entries before provider modules are loaded", %{
    conn: conn
  } do
    write_raw_session("session-a", [
      raw_entry(0, "user", %{
        "content" => "Hello from raw user",
        "timestamp" => "2026-05-24T15:17:32Z"
      }),
      raw_entry(1, "assistant", %{
        "content" => [%{"type" => "text", "text" => "Hello from raw assistant"}],
        "error_message" => nil,
        "model" => "gpt-5.5",
        "provider" => "openai_codex",
        "stop_reason" => "stop",
        "timestamp" => "2026-05-24T15:17:33Z",
        "usage" => nil
      })
    ])

    conn = get(conn, ~p"/sessions/session-a")

    response = html_response(conn, 200)
    assert response =~ "Hello from raw user"
    assert response =~ "Hello from raw assistant"
  end

  defp session(id) do
    now = DateTime.utc_now()

    %Session{
      id: id,
      created_at: now,
      updated_at: now
    }
  end

  defp append_messages(session, messages) do
    {session, _entries} = Session.append_messages(session, messages)
    session
  end

  defp write_raw_session(id, entries) do
    directory = Application.fetch_env!(:pado_web, :sessions_directory)
    File.mkdir_p!(directory)

    header = %{
      "type" => "session",
      "id" => id,
      "version" => 1,
      "created_at" => "2026-05-24T15:17:19Z",
      "updated_at" => "2026-05-24T15:19:59Z"
    }

    data =
      [header | entries]
      |> Enum.map(&Jason.encode!/1)
      |> Enum.join("\n")

    File.write!(Path.join(directory, id <> ".jsonl"), data <> "\n")
  end

  defp raw_entry(seq, kind, payload) do
    %{
      "type" => "entry",
      "id" => "entry-#{seq}",
      "seq" => seq,
      "kind" => kind,
      "payload" => payload,
      "refs" => %{},
      "timestamp" => "2026-05-24T15:17:32Z"
    }
  end
end
