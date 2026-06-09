defmodule Pado.AgentTest do
  use ExUnit.Case, async: true

  alias Pado.Agent
  alias Pado.Agent.Job
  alias Pado.Agent.Session
  alias Pado.Agent.Session.Entry
  alias Pado.AgentConfig
  alias Pado.AgentConfig.LLM
  alias Pado.LLM.Context
  alias Pado.LLM.Credential.OAuth.Credentials
  alias Pado.LLM.Message.{Assistant, User}
  alias Pado.LLM.Model
  alias Pado.LLM.Usage

  defmodule Store do
    @behaviour Pado.Agent.Session.Store

    def list(_opts), do: {:ok, []}

    def load(_session_id, _opts), do: {:error, :not_found}

    def save(session, opts) do
      send(Keyword.fetch!(opts, :owner), {:store_save, session})
      :ok
    end

    def append(session_id, entries, opts) do
      send(Keyword.fetch!(opts, :owner), {:store_append, session_id, entries})
      :ok
    end
  end

  setup tags do
    if tags[:fake_llm] do
      test_pid = self()

      Pado.Test.FakeLLM.setup_owner()
      on_exit(fn -> Pado.Test.FakeLLM.cleanup_owner(test_pid) end)
    end

    :ok
  end

  describe "spawn/5" do
    test "AgentConfig.build/5와 같은 인수로 agent를 만든다" do
      credentials = Credentials.build(:openai_codex, "a", "r", 3600)
      model = %Model{id: "codex", provider: :openai_codex}
      session = Session.new("session-1", timestamp: now())
      store = {Store, owner: self()}

      {:ok, agent} =
        Agent.spawn(:openai_codex, credentials, model, :high,
          router: Pado.Test.FakeLLM,
          session: session,
          store: store
        )

      assert_receive {:store_save, ^session}

      assert %{
               config: %AgentConfig{
                 llm: %LLM{
                   provider: :openai_codex,
                   credentials: ^credentials,
                   model: ^model,
                   router: Pado.Test.FakeLLM,
                   opts: [reasoning_effort: :high]
                 }
               },
               session: ^session,
               session_store: ^store
             } = :sys.get_state(agent)
    end
  end

  describe "handle_cast/2" do
    test ":abort_job은 실행 중인 job worker를 종료하고 aborted job_end를 보낸다" do
      {:ok, agent} = spawn_agent()
      agent_ref = Process.monitor(agent)

      collector =
        Task.async(fn ->
          agent
          |> Pado.Stream.subscribe()
          |> Enum.to_list()
        end)

      assert :ok = wait_until_subscriber_count(agent, 1)

      worker = spawn(fn -> Process.sleep(:infinity) end)
      worker_ref = Process.monitor(worker)
      job_worker_monitor = Process.monitor(worker)

      :sys.replace_state(agent, fn state ->
        %{
          state
          | job: %Job{messages: [], session_id: "s1", job_id: "j1"},
            job_worker_pid: worker,
            job_worker_monitor: job_worker_monitor
        }
      end)

      GenServer.cast(agent, :abort_job)

      assert_receive {:DOWN, ^worker_ref, :process, ^worker, :shutdown}, 500

      assert [{:job_end, %{job_id: "j1", status: :aborted, reason: nil, turns: []}}] =
               Task.await(collector, 500)

      assert_receive {:DOWN, ^agent_ref, :process, ^agent, :normal}, 500
    end
  end

  describe "세션 기반 실행" do
    @describetag :fake_llm

    test "세션 메시지로 Job을 만들고 종료 시 turn을 세션에 추가한다" do
      previous = %User{content: "previous", timestamp: now()}

      session = %{
        Session.new("session-1", timestamp: now())
        | entries: [entry(:user, previous, 0)]
      }

      assistant = %Assistant{content: [{:text, "ok"}], timestamp: now()}
      Pado.Test.FakeLLM.put_response(ok_stream(assistant))

      {:ok, agent} = spawn_agent(session: session)
      collector = collect_stream(agent)

      assert :ok = wait_until_subscriber_count(agent, 1)
      assert :ok = Agent.start(agent, %User{content: "next", timestamp: now()}, job_id: "job-1")

      assert_receive {:fake_router_called,
                      %{ctx: %Context{messages: [^previous, %User{content: "next"}]}}}

      events = Task.await(collector, 500)

      assert {:job_end, %{session: %Session{} = updated}} = List.last(events)
      assert Enum.map(updated.entries, & &1.kind) == [:user, :user, :assistant]
      assert Enum.map(updated.entries, & &1.seq) == [0, 1, 2]
      assert List.last(updated.entries).payload == assistant
    end

    test "세션 store가 있으면 초기 세션을 저장하고 새 엔트리를 append한다" do
      session = Session.new("session-1", timestamp: now())
      assistant = %Assistant{content: [{:text, "ok"}], timestamp: now()}
      Pado.Test.FakeLLM.put_response(ok_stream(assistant))

      {:ok, agent} = spawn_agent(session: session, store: {Store, owner: self()})
      assert_receive {:store_save, ^session}

      collector = collect_stream(agent)

      assert :ok = wait_until_subscriber_count(agent, 1)
      assert :ok = Agent.start(agent, "next", job_id: "job-1")

      assert_receive {:store_append, "session-1", [%Entry{kind: :user}]}

      events = Task.await(collector, 500)

      assert_receive {:store_append, "session-1", [%Entry{kind: :assistant}]}
      assert {:job_end, %{session: %Session{}}} = List.last(events)
    end

    test "tool turn마다 세션 store에 append한다" do
      tool = %Pado.AgentConfig.Tools.Tool{
        schema: Pado.LLM.Tool.new("echo", "d", %{}),
        async: fn _args, _ctx -> Task.async(fn -> "result" end) end,
        abort: fn task -> Task.shutdown(task, :brutal_kill) end
      }

      session = Session.new("session-1", timestamp: now())

      asst1 = %Assistant{
        content: [{:tool_call, %{id: "call-1", name: "echo", args: %{}}}],
        timestamp: now()
      }

      asst2 = %Assistant{content: [{:text, "done"}], timestamp: now()}

      Pado.Test.FakeLLM.put_responses([ok_stream(asst1), ok_stream(asst2)])

      {:ok, agent} = spawn_agent(tools: [tool], session: session, store: {Store, owner: self()})
      assert_receive {:store_save, ^session}

      collector = collect_stream(agent)

      assert :ok = wait_until_subscriber_count(agent, 1)
      assert :ok = Agent.start(agent, "next", job_id: "job-1")

      assert_receive {:store_append, "session-1", [%Entry{kind: :user}]}

      assert_receive {:store_append, "session-1",
                      [%Entry{kind: :assistant}, %Entry{kind: :tool_result}]}

      assert_receive {:store_append, "session-1", [%Entry{kind: :assistant}]}

      events = Task.await(collector, 500)

      assert {:job_end, %{session: %Session{} = updated, turns: [_, _]}} = List.last(events)
      assert Enum.map(updated.entries, & &1.kind) == [:user, :assistant, :tool_result, :assistant]
      refute_receive {:store_append, "session-1", _}, 50
    end

    test "세션 cwd를 tool context로 전달한다" do
      parent = self()

      tool = %Pado.AgentConfig.Tools.Tool{
        schema: Pado.LLM.Tool.new("echo", "d", %{}),
        async: fn _args, ctx ->
          send(parent, {:tool_ctx, ctx})
          Task.async(fn -> "result" end)
        end,
        abort: fn task -> Task.shutdown(task, :brutal_kill) end
      }

      session = Session.new("session-1", cwd: "/tmp/pado-workspace", timestamp: now())

      assistant = %Assistant{
        content: [{:tool_call, %{id: "call-1", name: "echo", args: %{}}}],
        timestamp: now()
      }

      Pado.Test.FakeLLM.put_response(ok_stream(assistant))

      {:ok, agent} = spawn_agent(tools: [tool], session: session)
      collector = collect_stream(agent)

      assert :ok = wait_until_subscriber_count(agent, 1)
      assert :ok = Agent.start(agent, "next", job_id: "job-1")

      events = Task.await(collector, 500)

      assert_receive {:tool_ctx, %{cwd: "/tmp/pado-workspace"}}
      assert {:job_end, %{session: %Session{}}} = List.last(events)
    end

    test "세션 없이 메시지로 시작하면 에러를 반환한다" do
      {:ok, agent} = spawn_agent()

      assert {:error, :missing_session} = Agent.start(agent, "next")

      Process.exit(agent, :kill)
    end
  end

  defp wait_until_subscriber_count(pid, count, retries \\ 50)

  defp wait_until_subscriber_count(_pid, _count, 0), do: :error

  defp wait_until_subscriber_count(pid, count, retries) do
    case :sys.get_state(pid) do
      %{subscribers: subscribers} when map_size(subscribers) == count ->
        :ok

      _ ->
        Process.sleep(10)
        wait_until_subscriber_count(pid, count, retries - 1)
    end
  end

  defp spawn_agent(opts \\ []) do
    Agent.spawn(
      :openai_codex,
      Keyword.get(opts, :credentials, Credentials.build(:openai_codex, "a", "r", 3600)),
      Keyword.get(opts, :model, %Model{id: "test", provider: :openai_codex}),
      Keyword.get(opts, :reasoning_effort),
      Keyword.put_new(opts, :router, Pado.Test.FakeLLM)
    )
  end

  defp collect_stream(agent) do
    Task.async(fn ->
      agent
      |> Pado.Stream.subscribe()
      |> Enum.to_list()
    end)
  end

  defp ok_stream(final_assistant) do
    {:ok,
     [
       {:start, %{message: %Assistant{}}},
       {:done, %{stop_reason: :stop, usage: Usage.empty(), message: final_assistant}}
     ]}
  end

  defp entry(kind, payload, seq) do
    %Entry{
      id: "entry-#{seq}",
      seq: seq,
      kind: kind,
      payload: payload,
      timestamp: now()
    }
  end

  defp now, do: ~U[2026-05-17 12:00:00Z]
end
