defmodule PadoWebWeb.SessionLiveTest do
  use PadoWebWeb.ConnCase

  alias Pado.Agent.Session
  alias Pado.Agent.Session.Store
  alias Pado.LLM.Credential.OAuth.Credentials
  alias Pado.LLM.Message
  alias Pado.LLM.Message.{Assistant, User}

  import Phoenix.LiveViewTest

  defmodule FakeRouter do
    alias Pado.LLM.Message.Assistant

    def stream(model, ctx, creds, session_id, opts) do
      owner = Application.fetch_env!(:pado_web, :session_live_test_owner)
      mode = Application.get_env(:pado_web, :session_live_test_router_mode, :immediate)

      send(
        owner,
        {:fake_router_called,
         %{model: model, ctx: ctx, creds: creds, session_id: session_id, opts: opts}}
      )

      {:ok, fake_stream(owner, mode, model)}
    end

    defp fake_stream(owner, :delayed, model) do
      Stream.resource(
        fn ->
          send(owner, {:fake_router_delaying, self()})
          :delaying
        end,
        fn
          :delaying ->
            Process.sleep(800)

            {[
               {:start, %{message: %Assistant{provider: model.provider, model: model.id}}},
               {:text_delta, %{index: 0, delta: "Hello "}},
               {:text_delta, %{index: 0, delta: "from stream"}},
               {:done,
                %{
                  message: %Assistant{
                    content: [{:text, "Hello from stream"}],
                    provider: model.provider,
                    model: model.id
                  }
                }}
             ], :done}

          :done ->
            {:halt, :done}
        end,
        fn _state -> :ok end
      )
    end

    defp fake_stream(owner, :thinking_then_text, model) do
      Stream.resource(
        fn -> :thinking end,
        fn
          :thinking ->
            send(owner, {:fake_router_stream_stage, :thinking, self()})

            {[
               {:start, %{message: %Assistant{provider: model.provider, model: model.id}}},
               {:thinking_delta, %{index: 0, delta: "Thinking through it"}}
             ], :text}

          :text ->
            receive do
              :release_text_delta ->
                send(owner, {:fake_router_stream_stage, :text, self()})
                {[{:text_delta, %{index: 0, delta: "Hello visible text"}}], :done}
            end

          :done ->
            receive do
              :release_done ->
                {[
                   {:done,
                    %{
                      message: %Assistant{
                        content: [{:text, "Hello visible text"}],
                        provider: model.provider,
                        model: model.id
                      }
                    }}
                 ], :halt}
            end

          :halt ->
            {:halt, :halt}
        end,
        fn _state -> :ok end
      )
    end

    defp fake_stream(_owner, _mode, model) do
      [
        {:start, %{message: %Assistant{provider: model.provider, model: model.id}}},
        {:done,
         %{
           message: %Assistant{
             content: [{:text, "Hello from agent"}],
             provider: model.provider,
             model: model.id
           }
         }}
      ]
    end
  end

  defmodule FakeCredsLoader do
    def load(_owner) do
      {:ok, Credentials.build(:openai_codex, "access", "refresh", 3600)}
    end

    def save(_creds, _owner), do: :ok
  end

  setup do
    directory =
      System.tmp_dir!()
      |> Path.join("pado-web-session-live-#{System.unique_integer([:positive])}")

    previous = Application.get_env(:pado_web, :sessions_directory)
    previous_router = Application.get_env(:pado_web, :llm_router)
    previous_owner = Application.get_env(:pado_web, :session_live_test_owner)
    previous_router_mode = Application.get_env(:pado_web, :session_live_test_router_mode)
    previous_credentials = Application.get_env(:pado, :credentials)

    Application.put_env(:pado_web, :sessions_directory, directory)
    Application.put_env(:pado_web, :llm_router, FakeRouter)
    Application.put_env(:pado_web, :session_live_test_owner, self())
    Application.delete_env(:pado_web, :session_live_test_router_mode)

    Application.put_env(:pado, :credentials, %{
      openai_codex: {FakeCredsLoader, self()}
    })

    on_exit(fn ->
      if previous do
        Application.put_env(:pado_web, :sessions_directory, previous)
      else
        Application.delete_env(:pado_web, :sessions_directory)
      end

      if previous_router do
        Application.put_env(:pado_web, :llm_router, previous_router)
      else
        Application.delete_env(:pado_web, :llm_router)
      end

      if previous_owner do
        Application.put_env(:pado_web, :session_live_test_owner, previous_owner)
      else
        Application.delete_env(:pado_web, :session_live_test_owner)
      end

      if previous_router_mode do
        Application.put_env(:pado_web, :session_live_test_router_mode, previous_router_mode)
      else
        Application.delete_env(:pado_web, :session_live_test_router_mode)
      end

      if previous_credentials do
        Application.put_env(:pado, :credentials, previous_credentials)
      else
        Application.delete_env(:pado, :credentials)
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
    assert response =~ ~s(aria-label="New session")
  end

  test "GET /sessions lists stored sessions", %{conn: conn, store: store} do
    :ok = Store.save(store, Session.new("session-a"))
    :ok = Store.save(store, Session.new("session-b"))

    conn = get(conn, ~p"/sessions")

    response = html_response(conn, 200)
    assert response =~ "session-a"
    assert response =~ "session-b"
    assert response =~ ~s(href="/sessions/session-a")
  end

  test "clicking New session creates a default session and opens it", %{conn: conn, store: store} do
    {:ok, view, _html} = live(conn, ~p"/sessions")

    view
    |> element(~s(button[aria-label="New session"]))
    |> render_click()

    path = assert_patch(view)
    assert path =~ ~r|^/sessions/session-|

    assert {:ok, [summary]} = Store.list(store)
    assert path == ~p"/sessions/#{summary.id}"

    assert {:ok,
            %Session{
              id: session_id,
              provider: :openai_codex,
              model: "gpt-5.4-mini",
              reasoning_effort: :medium,
              entries: []
            }} = Store.load(store, summary.id)

    assert session_id == summary.id
    assert render(view) =~ session_id
  end

  test "GET /sessions/:id marks the selected session", %{conn: conn, store: store} do
    :ok = Store.save(store, Session.new("session-a"))

    conn = get(conn, ~p"/sessions/session-a")

    response = html_response(conn, 200)
    assert response =~ "Active session"
    assert response =~ "session-a"
    assert response =~ "status-primary"
    refute response =~ "status-success"
  end

  test "GET /sessions/:id renders stored messages", %{conn: conn, store: store} do
    session =
      "session-a"
      |> Session.new()
      |> append_messages([
        User.new("Hello from user"),
        %Assistant{
          content: [
            {:thinking, "Stored thinking"},
            {:text, "Hello from assistant"}
          ]
        }
      ])

    :ok = Store.save(store, session)

    conn = get(conn, ~p"/sessions/session-a")

    response = html_response(conn, 200)
    assert response =~ "Hello from user"
    assert response =~ "Stored thinking"
    assert response =~ "Hello from assistant"
    assert response =~ ~s(data-entry-kind="user")
    assert response =~ ~s(data-entry-kind="assistant")
    assert response =~ ~s(data-content-kind="thinking")
    assert response =~ ~s(data-content-kind="text")
    assert response =~ ~s(id="session-entry-list")
    assert response =~ ~s(phx-hook="SessionScroll")
    assert response =~ "rounded-lg"
    refute response =~ "chat-bubble"
    refute response =~ "Assistant"
    refute response =~ ~r/<p[^>]*>\s+Hello from assistant/
  end

  test "GET /sessions/:id renders assistant errors as errors", %{conn: conn, store: store} do
    session =
      "session-a"
      |> Session.new()
      |> append_messages([
        User.new("Please answer slowly"),
        %Assistant{
          content: [],
          stop_reason: :error,
          error_message: "Finch stream error: %Mint.TransportError{reason: :timeout}"
        }
      ])

    :ok = Store.save(store, session)

    conn = get(conn, ~p"/sessions/session-a")

    response = html_response(conn, 200)
    assert response =~ "Please answer slowly"
    assert response =~ "Response timed out"
    assert response =~ "Finch stream error"
    assert response =~ "alert-error"
    assert response =~ ~s(data-content-kind="error")
    refute response =~ "No text content."
  end

  test "GET /sessions/:id renders the chat composer", %{conn: conn, store: store} do
    :ok = Store.save(store, Session.new("session-a"))

    conn = get(conn, ~p"/sessions/session-a")

    response = html_response(conn, 200)
    assert response =~ ~s(data-chat-composer)
    assert response =~ ~s(id="chat-composer-session-a")
    assert response =~ ~s(phx-hook="ChatComposer")
    assert response =~ ~s(name="message")
    assert response =~ "bg-base-200/80"
    assert response =~ "textarea-ghost"
    refute response =~ "textarea-bordered"
    assert response =~ "Message session-a"
    assert response =~ ~r/<textarea[^>]*class="[^"]*\bw-full\b/
    assert response =~ ~s(aria-label="Send message")
    assert response =~ "btn-square"
    assert response =~ "rounded-full"
    refute response =~ ~r/<span>\s*Send\s*<\/span>/
  end

  test "selecting a model updates the selected session", %{conn: conn, store: store} do
    :ok = Store.save(store, Session.new("session-a"))

    {:ok, view, _html} = live(conn, ~p"/sessions/session-a")

    view
    |> element(~s(button[phx-click="select_model"][phx-value-model="gpt-5.5"]))
    |> render_click()

    assert {:ok, %Session{model: "gpt-5.5", provider: :openai_codex}} =
             Store.load(store, "session-a")

    assert render(view) =~ "5.5"
  end

  test "selecting intelligence updates the selected session", %{conn: conn, store: store} do
    :ok = Store.save(store, Session.new("session-a"))

    {:ok, view, _html} = live(conn, ~p"/sessions/session-a")

    view
    |> element(~s(button[phx-click="select_reasoning_effort"][phx-value-effort="high"]))
    |> render_click()

    assert {:ok, %Session{reasoning_effort: :high}} = Store.load(store, "session-a")
    assert render(view) =~ "High"
  end

  test "submitting the chat composer runs the agent and stores the turn", %{
    conn: conn,
    store: store
  } do
    :ok = Store.save(store, Session.new("session-a"))

    {:ok, view, _html} = live(conn, ~p"/sessions/session-a")

    html =
      view
      |> form("form[data-chat-composer]", %{message: "Hello from composer"})
      |> render_submit()

    assert html =~ "Hello from composer"

    assert_push_event view, "clear-chat-composer", %{id: "chat-composer-session-a"}

    assert_receive {:fake_router_called,
                    %{session_id: "session-a", opts: [reasoning_effort: "medium"]}}

    assert eventually(fn ->
             render(view) =~ "Hello from agent"
           end)

    assert {:ok, saved_session} = Store.load(store, "session-a")

    assert [%{kind: :user, payload: user}, %{kind: :assistant, payload: assistant}] =
             saved_session.entries

    assert Message.text(user) == "Hello from composer"
    assert Message.text(assistant) == "Hello from agent"
  end

  test "submitting the chat composer does not wait for the agent stream to finish", %{
    conn: conn,
    store: store
  } do
    Application.put_env(:pado_web, :session_live_test_router_mode, :delayed)

    :ok = Store.save(store, Session.new("session-a"))

    {:ok, view, _html} = live(conn, ~p"/sessions/session-a")

    started_at = System.monotonic_time(:millisecond)

    html =
      view
      |> form("form[data-chat-composer]", %{message: "Hello while streaming"})
      |> render_submit()

    duration = System.monotonic_time(:millisecond) - started_at

    assert_receive {:fake_router_delaying, _router_pid}, 1_000
    assert duration < 500
    assert html =~ "Hello while streaming"
    refute html =~ "Hello from stream"
    assert_push_event view, "clear-chat-composer", %{id: "chat-composer-session-a"}

    assert eventually(fn ->
             render(view) =~ "Hello from stream"
           end)
  end

  test "streaming thinking remains visible after text starts", %{
    conn: conn,
    store: store
  } do
    Application.put_env(:pado_web, :session_live_test_router_mode, :thinking_then_text)

    :ok = Store.save(store, Session.new("session-a"))

    {:ok, view, _html} = live(conn, ~p"/sessions/session-a")

    view
    |> form("form[data-chat-composer]", %{message: "Think then answer"})
    |> render_submit()

    assert_receive {:fake_router_stream_stage, :thinking, router_pid}, 1_000

    assert eventually(fn ->
             render(view) =~ "Thinking through it"
           end)

    send(router_pid, :release_text_delta)
    assert_receive {:fake_router_stream_stage, :text, ^router_pid}, 1_000

    assert eventually(fn ->
             html = render(view)

             html =~ ~s(id="session-streaming-entry-session-a-thinking") and
               html =~ ~s(id="session-streaming-entry-session-a-text") and
               html =~ "Thinking through it" and
               html =~ "Hello visible text"
           end)

    send(router_pid, :release_done)

    assert eventually(fn ->
             render(view) =~ "Hello visible text"
           end)
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

  defp eventually(fun, attempts \\ 20)

  defp eventually(fun, attempts) when attempts > 0 do
    if fun.() do
      true
    else
      Process.sleep(50)
      eventually(fun, attempts - 1)
    end
  end

  defp eventually(_fun, 0), do: false
end
