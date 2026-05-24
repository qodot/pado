defmodule PadoWebWeb.SessionLiveTest do
  use PadoWebWeb.ConnCase

  alias Pado.Agent.Session
  alias Pado.Agent.Session.Store

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

  defp session(id) do
    now = DateTime.utc_now()

    %Session{
      id: id,
      created_at: now,
      updated_at: now
    }
  end
end
