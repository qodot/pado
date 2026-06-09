defmodule Pado.StreamTest.FakeAgent do
  use GenServer

  def start(owner) do
    GenServer.start(__MODULE__, owner)
  end

  @impl true
  def init(owner) do
    {:ok, %{owner: owner, subscribers: %{}}}
  end

  @impl true
  def handle_call({:subscribe, subscriber, stream_ref}, _from, state) do
    count = map_size(state.subscribers) + 1
    send(state.owner, {:subscribed, self(), subscriber, stream_ref, count})

    {:reply, :ok, %{state | subscribers: Map.put(state.subscribers, stream_ref, subscriber)}}
  end

  @impl true
  def handle_call({:emit, event}, _from, state) do
    Enum.each(state.subscribers, fn {stream_ref, subscriber} ->
      send(subscriber, {stream_ref, event})
    end)

    {:reply, :ok, state}
  end

  @impl true
  def handle_call({:emit_to, stream_ref, event}, _from, state) do
    if subscriber = Map.get(state.subscribers, stream_ref) do
      send(subscriber, {stream_ref, event})
    end

    {:reply, :ok, state}
  end

  @impl true
  def handle_call(:subscribers, _from, state) do
    {:reply, state.subscribers, state}
  end

  @impl true
  def handle_cast({:unsubscribe, subscriber, stream_ref}, state) do
    send(state.owner, {:unsubscribed, self(), subscriber, stream_ref})
    {:noreply, %{state | subscribers: Map.delete(state.subscribers, stream_ref)}}
  end
end

defmodule Pado.StreamTest do
  use ExUnit.Case, async: true

  alias Pado.Agent
  alias Pado.Agent.Session
  alias Pado.AgentConfig
  alias Pado.AgentConfig.Tools.Tool
  alias Pado.LLM.{Model, Usage}
  alias Pado.LLM.Credential.OAuth.Credentials
  alias Pado.LLM.Message.Assistant
  alias Pado.LLM.Tool, as: LLMTool

  defmodule Store do
    @behaviour Pado.Agent.Session.Store

    def list(_opts), do: {:ok, []}

    def load(session_id, opts) do
      case Keyword.get(opts, :session) do
        %Session{id: ^session_id} = session -> {:ok, session}
        _other -> {:error, :not_found}
      end
    end

    def save(_session, _opts), do: :ok
    def append(_session_id, _entries, _opts), do: :ok
  end

  setup tags do
    if tags[:fake_llm] do
      test_pid = self()

      Pado.Test.FakeLLM.setup_owner()
      on_exit(fn -> Pado.Test.FakeLLM.cleanup_owner(test_pid) end)
    end

    :ok
  end

  describe "subscribe/1 단위 동작" do
    test "pid가 아니면 함수 절 오류가 난다" do
      assert_raise FunctionClauseError, fn -> apply(Pado.Stream, :subscribe, [:agent]) end
    end

    test "열거 전에는 agent에 구독하지 않는다" do
      agent = start_fake_agent()
      stream = Pado.Stream.subscribe(agent)

      assert is_function(stream)
      refute_receive {:subscribed, ^agent, _, _, _}, 20

      collector = Task.async(fn -> Enum.take(stream, 1) end)
      {subscriber, stream_ref} = assert_subscribed(agent)

      send(subscriber, {stream_ref, :ready})

      assert [:ready] = Task.await(collector, 500)
      assert_unsubscribed(agent, subscriber, stream_ref)
    end

    test "열거한 프로세스를 subscriber로 등록한다" do
      agent = start_fake_agent()
      stream = Pado.Stream.subscribe(agent)

      collector = Task.async(fn -> Enum.take(stream, 1) end)
      {subscriber, stream_ref} = assert_subscribed(agent)

      assert subscriber == collector.pid

      send(subscriber, {stream_ref, :event})

      assert [:event] = Task.await(collector, 500)
      assert_unsubscribed(agent, subscriber, stream_ref)
    end

    test "여러 스트림은 서로 다른 stream_ref로 이벤트를 분리한다" do
      agent = start_fake_agent()

      collector1 = Task.async(fn -> agent |> Pado.Stream.subscribe() |> Enum.take(1) end)
      collector2 = Task.async(fn -> agent |> Pado.Stream.subscribe() |> Enum.take(1) end)

      {subscriber1, stream_ref1} = assert_subscribed(agent)
      {subscriber2, stream_ref2} = assert_subscribed(agent)

      assert stream_ref1 != stream_ref2

      assert MapSet.new([subscriber1, subscriber2]) ==
               MapSet.new([collector1.pid, collector2.pid])

      send(subscriber1, {stream_ref1, {:for, subscriber1}})
      send(subscriber2, {stream_ref2, {:for, subscriber2}})

      results = [Task.await(collector1, 500), Task.await(collector2, 500)]

      assert MapSet.new(List.flatten(results)) ==
               MapSet.new([{:for, subscriber1}, {:for, subscriber2}])

      assert_unsubscribed(agent, subscriber1, stream_ref1)
      assert_unsubscribed(agent, subscriber2, stream_ref2)
    end

    test "다른 stream_ref로 온 메시지는 무시한다" do
      agent = start_fake_agent()
      collector = Task.async(fn -> agent |> Pado.Stream.subscribe() |> Enum.take(1) end)
      {subscriber, stream_ref} = assert_subscribed(agent)

      send(subscriber, {make_ref(), :ignored})
      refute Task.yield(collector, 30)

      send(subscriber, {stream_ref, :accepted})

      assert [:accepted] = Task.await(collector, 500)
      assert_unsubscribed(agent, subscriber, stream_ref)
    end

    test ":job_end를 내보낸 뒤 스트림을 종료한다" do
      agent = start_fake_agent()
      end_event = {:job_end, %{job_id: "j1", status: :done, reason: nil, turns: []}}

      collector = Task.async(fn -> agent |> Pado.Stream.subscribe() |> Enum.to_list() end)
      {subscriber, stream_ref} = assert_subscribed(agent)

      send(subscriber, {stream_ref, :first})
      send(subscriber, {stream_ref, end_event})
      send(subscriber, {stream_ref, :late})

      assert [:first, ^end_event] = Task.await(collector, 500)
      assert_unsubscribed(agent, subscriber, stream_ref)
    end

    test "구독 중 agent가 종료되면 에러 job_end를 내보낸다" do
      agent = start_fake_agent()
      parent = self()

      collector =
        Task.async(fn ->
          agent
          |> Pado.Stream.subscribe()
          |> Stream.each(fn event -> send(parent, {:stream_event, event}) end)
          |> Enum.take(2)
        end)

      {subscriber, stream_ref} = assert_subscribed(agent)
      send(subscriber, {stream_ref, :before_down})
      assert_receive {:stream_event, :before_down}, 500

      Process.exit(agent, :kill)

      assert [
               :before_down,
               {:job_end, %{job_id: nil, status: :error, reason: :killed, turns: []}}
             ] = Task.await(collector, 500)
    end

    test "이미 종료된 pid를 구독하면 즉시 에러 job_end를 반환한다" do
      pid = spawn(fn -> :ok end)
      assert :ok = wait_until_dead(pid)

      assert [
               {:job_end, %{job_id: nil, status: :error, reason: {:noproc, _}, turns: []}}
             ] = pid |> Pado.Stream.subscribe() |> Enum.to_list()
    end

    test "스트림 소비를 중단하면 agent에 구독 해제를 보낸다" do
      agent = start_fake_agent()
      collector = Task.async(fn -> agent |> Pado.Stream.subscribe() |> Enum.take(1) end)
      {subscriber, stream_ref} = assert_subscribed(agent)

      :ok = GenServer.call(agent, {:emit_to, stream_ref, :one})

      assert [:one] = Task.await(collector, 500)
      assert_unsubscribed(agent, subscriber, stream_ref)

      assert GenServer.call(agent, :subscribers) == %{}
    end

    test "agent가 보낸 일반 이벤트를 순서대로 전달한다" do
      agent = start_fake_agent()
      end_event = {:job_end, %{job_id: "j1", status: :done, reason: nil, turns: []}}

      collector = Task.async(fn -> agent |> Pado.Stream.subscribe() |> Enum.to_list() end)
      {subscriber, stream_ref} = assert_subscribed(agent)

      :ok = GenServer.call(agent, {:emit, :one})
      :ok = GenServer.call(agent, {:emit, :two})
      send(subscriber, {stream_ref, end_event})

      assert [:one, :two, ^end_event] = Task.await(collector, 500)
      assert_unsubscribed(agent, subscriber, stream_ref)
    end
  end

  describe "Agent 통합 경로" do
    @describetag :fake_llm

    test "1턴 응답 → :job_start로 시작, :job_end status :done" do
      Pado.Test.FakeLLM.put_response(ok_stream(%Assistant{content: [{:text, "ok"}]}))

      config = build_setup([])
      {:ok, agent} = spawn_agent(config)
      collector = collect_stream(agent)

      assert :ok = wait_until_subscriber_count(agent, 1)
      :ok = start_job(agent)

      events = Task.await(collector, 500)

      assert {:job_start, %{job_id: job_id}} = hd(events)
      assert is_binary(job_id)
      assert {:job_end, %{status: :done, reason: nil, turns: [_]}} = List.last(events)
    end

    test "tool_call 후 다음 turn → turn_start 2번, :done으로 종료" do
      tool = make_tool("echo", fn _, _ -> "r" end)

      asst1 = %Assistant{content: [{:tool_call, %{id: "c1", name: "echo", args: %{}}}]}
      asst2 = %Assistant{content: [{:text, "final"}]}
      Pado.Test.FakeLLM.put_responses([ok_stream(asst1), ok_stream(asst2)])

      config = build_setup(tools: [tool])
      {:ok, agent} = spawn_agent(config)
      collector = collect_stream(agent)

      assert :ok = wait_until_subscriber_count(agent, 1)
      :ok = start_job(agent)

      events = Task.await(collector, 500)

      turn_starts = Enum.filter(events, &match?({:turn_start, _}, &1))
      assert length(turn_starts) == 2

      assert {:job_end, %{status: :done, turns: [_, _]}} = List.last(events)
    end

    test "기본 max_turns 도달 시 :max_turns" do
      tool = make_tool("echo", fn _, _ -> "r" end)
      asst = %Assistant{content: [{:tool_call, %{id: "c1", name: "echo", args: %{}}}]}
      Pado.Test.FakeLLM.put_response(ok_stream(asst))

      config = build_setup(tools: [tool])
      {:ok, agent} = spawn_agent(config)
      collector = collect_stream(agent)

      assert :ok = wait_until_subscriber_count(agent, 1)
      :ok = start_job(agent)

      events = Task.await(collector, 500)
      assert {:job_end, %{status: :max_turns, turns: turns}} = List.last(events)
      assert length(turns) == 10
    end

    test "LLM 응답이 :error로 끝나면 :job_end status :error에 reason 실림" do
      error_msg = %Assistant{stop_reason: :error, error_message: "boom"}

      Pado.Test.FakeLLM.put_response(
        {:ok,
         [
           {:start, %{message: %Assistant{}}},
           {:error,
            %{reason: :error, error_message: "boom", message: error_msg, usage: Usage.empty()}}
         ]}
      )

      config = build_setup([])
      {:ok, agent} = spawn_agent(config)
      collector = collect_stream(agent)

      assert :ok = wait_until_subscriber_count(agent, 1)
      :ok = start_job(agent)

      assert {:job_end, %{status: :error, reason: "boom"}} =
               collector |> Task.await(500) |> List.last()
    end
  end

  describe "Agent 구독자 라이프사이클 통합 경로" do
    @describetag :fake_llm

    test "여러 번 호출하면 각각 스트림을 반환한다" do
      config = build_setup([])
      {:ok, agent} = spawn_agent(config)

      assert stream1 = Pado.Stream.subscribe(agent)
      assert stream2 = Pado.Stream.subscribe(agent)
      assert is_function(stream1)
      assert is_function(stream2)

      Process.exit(agent, :kill)
    end

    test "이미 종료된 agent를 구독하면 에러 종료 이벤트 스트림을 반환한다" do
      Pado.Test.FakeLLM.put_response(ok_stream(%Assistant{content: [{:text, "ok"}]}))

      config = build_setup([])
      {:ok, agent} = spawn_agent(config)

      :ok = start_job(agent)

      stream = Pado.Stream.subscribe(agent)
      _ = Enum.to_list(stream)

      wait_until_dead(agent)

      stream = Pado.Stream.subscribe(agent)
      assert [{:job_end, %{job_id: nil, status: :error, turns: []}}] = Enum.to_list(stream)
    end

    test "여러 구독자가 같은 job의 이후 이벤트를 받는다" do
      Pado.Test.FakeLLM.put_response(
        gated_ok_stream(self(), %Assistant{content: [{:text, "ok"}]})
      )

      config = build_setup([])
      {:ok, agent} = spawn_agent(config)

      :ok = start_job(agent)

      subscriber1 =
        Task.async(fn ->
          stream = Pado.Stream.subscribe(agent)
          Enum.to_list(stream)
        end)

      assert_receive {:llm_stream_waiting, worker_pid}, 500

      subscriber2 =
        Task.async(fn ->
          stream = Pado.Stream.subscribe(agent)
          Enum.to_list(stream)
        end)

      assert :ok = wait_until_subscriber_count(agent, 2)

      send(worker_pid, :release_llm_stream)

      events1 = Task.await(subscriber1, 500)
      events2 = Task.await(subscriber2, 500)

      assert {:job_end, %{status: :done}} = List.last(events1)
      assert {:job_end, %{status: :done}} = List.last(events2)

      assert Enum.any?(events1, &match?({:message_start, _}, &1))
      assert Enum.any?(events2, &match?({:message_start, _}, &1))
    end

    test "구독자 하나가 죽어도 다른 구독자가 남아 있으면 agent는 유지된다" do
      Pado.Test.FakeLLM.put_response(
        gated_ok_stream(self(), %Assistant{content: [{:text, "ok"}]})
      )

      config = build_setup([])
      {:ok, agent} = spawn_agent(config)

      :ok = start_job(agent)

      live_subscriber =
        Task.async(fn ->
          stream = Pado.Stream.subscribe(agent)
          Enum.to_list(stream)
        end)

      assert_receive {:llm_stream_waiting, worker_pid}, 500

      dead_subscriber =
        spawn(fn ->
          stream = Pado.Stream.subscribe(agent)
          Enum.to_list(stream)
        end)

      assert :ok = wait_until_subscriber_count(agent, 2)

      dead_ref = Process.monitor(dead_subscriber)
      Process.exit(dead_subscriber, :kill)
      assert_receive {:DOWN, ^dead_ref, :process, ^dead_subscriber, :killed}, 500

      assert :ok = wait_until_subscriber_count(agent, 1)
      assert Process.alive?(agent)

      send(worker_pid, :release_llm_stream)

      assert {:job_end, %{status: :done}} = live_subscriber |> Task.await(500) |> List.last()
    end

    test "마지막 구독자가 stream을 중단하면 agent도 정리된다" do
      Pado.Test.FakeLLM.put_response(
        gated_ok_stream(self(), %Assistant{content: [{:text, "ok"}]})
      )

      config = build_setup([])
      {:ok, agent} = spawn_agent(config)
      ref = Process.monitor(agent)

      subscriber =
        Task.async(fn ->
          Pado.Stream.subscribe(agent)
          |> Enum.take(1)
        end)

      assert :ok = wait_until_subscriber_count(agent, 1)
      :ok = start_job(agent)

      assert [{:job_start, %{job_id: job_id}}] = Task.await(subscriber, 500)
      assert is_binary(job_id)
      assert_receive {:DOWN, ^ref, :process, ^agent, _}, 500
    end
  end

  defp start_fake_agent do
    {:ok, agent} = Pado.StreamTest.FakeAgent.start(self())
    agent
  end

  defp assert_subscribed(agent) do
    assert_receive {:subscribed, ^agent, subscriber, stream_ref, _count}, 500
    {subscriber, stream_ref}
  end

  defp assert_unsubscribed(agent, subscriber, stream_ref) do
    assert_receive {:unsubscribed, ^agent, ^subscriber, ^stream_ref}, 500
  end

  defp wait_until_dead(pid, retries \\ 50)

  defp wait_until_dead(_pid, 0), do: :error

  defp wait_until_dead(pid, retries) do
    if Process.alive?(pid) do
      Process.sleep(10)
      wait_until_dead(pid, retries - 1)
    else
      :ok
    end
  end

  defp wait_until_subscriber_count(pid, count, retries \\ 50)

  defp wait_until_subscriber_count(_pid, _count, 0), do: :error

  defp wait_until_subscriber_count(pid, count, retries) do
    try do
      case :sys.get_state(pid) do
        %{subscribers: subscribers} when map_size(subscribers) == count ->
          :ok

        _ ->
          Process.sleep(10)
          wait_until_subscriber_count(pid, count, retries - 1)
      end
    catch
      :exit, _ -> :error
    end
  end

  defp collect_stream(agent) do
    Task.async(fn ->
      agent
      |> Pado.Stream.subscribe()
      |> Enum.to_list()
    end)
  end

  defp spawn_agent(%AgentConfig{} = config) do
    Agent.spawn(
      config.llm.provider,
      config.llm.credentials,
      config.llm.model,
      Keyword.get(config.llm.opts, :reasoning_effort),
      {Store, session: Session.new("s1")},
      router: config.llm.router,
      tools: config.harness.tools
    )
  end

  defp start_job(agent) do
    Agent.run(agent, "s1", "hi")
  end

  defp build_setup(opts) do
    %AgentConfig{
      llm: %AgentConfig.LLM{
        provider: :openai_codex,
        credentials: Credentials.build(:openai_codex, "a", "r", 3600),
        model: %Model{id: "test", provider: :test}
      },
      harness: %AgentConfig.Harness{
        tools: Keyword.get(opts, :tools, [])
      }
    }
  end

  defp make_tool(name, execute) do
    %Tool{
      schema: LLMTool.new(name, "d", %{}),
      async: fn args, ctx -> Task.async(fn -> execute.(args, ctx) end) end,
      abort: fn task -> Task.shutdown(task, :brutal_kill) end
    }
  end

  defp ok_stream(final_assistant) do
    {:ok,
     [
       {:start, %{message: %Assistant{}}},
       {:done, %{stop_reason: :stop, usage: Usage.empty(), message: final_assistant}}
     ]}
  end

  defp gated_ok_stream(parent, final_assistant) do
    {:ok,
     Stream.resource(
       fn ->
         send(parent, {:llm_stream_waiting, self()})
         :waiting
       end,
       fn
         :waiting ->
           receive do
             :release_llm_stream ->
               {[
                  {:start, %{message: %Assistant{}}},
                  {:done, %{stop_reason: :stop, usage: Usage.empty(), message: final_assistant}}
                ], :done}
           end

         :done ->
           {:halt, :done}
       end,
       fn _ -> :ok end
     )}
  end
end
