defmodule Pado.Agent.TurnTest do
  use ExUnit.Case, async: true

  alias Pado.Agent.{Job, Turn}
  alias Pado.LLMRouter.{Context, Model, Usage}
  alias Pado.LLMRouter.Message.{Assistant, ToolResult, User}
  alias Pado.LLMRouter.OAuth.Credentials

  describe "as_llm_messages/1" do
    test "users, assistant, tool_results를 시간순으로 펼친다" do
      users = [User.new("X 해줘")]
      assistant = %Assistant{content: [{:text, "ok"}]}

      tool_results = [
        ToolResult.text("c1", "search", "결과 1"),
        ToolResult.text("c2", "fetch", "결과 2")
      ]

      turn = %Turn{
        index: 1,
        users: users,
        assistant: assistant,
        tool_results: tool_results
      }

      assert Turn.as_llm_messages(turn) == users ++ [assistant] ++ tool_results
    end

    test "users가 비어 있으면 assistant + tool_results만" do
      assistant = %Assistant{content: [{:text, "hi"}]}
      tr = ToolResult.text("c1", "t", "r")

      turn = %Turn{
        index: 1,
        users: [],
        assistant: assistant,
        tool_results: [tr]
      }

      assert Turn.as_llm_messages(turn) == [assistant, tr]
    end

    test "tool_results가 비어 있으면 users + assistant만" do
      users = [User.new("X")]
      assistant = %Assistant{content: [{:text, "y"}]}

      turn = %Turn{
        index: 1,
        users: users,
        assistant: assistant,
        tool_results: []
      }

      assert Turn.as_llm_messages(turn) == users ++ [assistant]
    end

    test "users와 tool_results 둘 다 비어 있으면 assistant만" do
      assistant = %Assistant{content: [{:text, "only"}]}

      turn = %Turn{index: 1, assistant: assistant}

      assert Turn.as_llm_messages(turn) == [assistant]
    end
  end

  describe "consume_llm_stream/3" do
    setup do
      test_pid = self()
      emit = fn ev -> send(test_pid, {:emitted, ev}) end
      {:ok, emit: emit}
    end

    test ":start → :done 만 있는 스트림은 {:ok, message} 반환", %{emit: emit} do
      msg = %Assistant{content: [{:text, "hi"}]}

      events = [
        {:start, %{message: %Assistant{}}},
        {:done, %{stop_reason: :stop, usage: Usage.empty(), message: msg}}
      ]

      assert {:ok, ^msg} = Turn.consume_llm_stream(events, "job-1", emit)
    end

    test ":start → :error는 {:error, message} 반환", %{emit: emit} do
      msg = %Assistant{content: [{:text, "boom"}], stop_reason: :error}

      events = [
        {:start, %{message: %Assistant{}}},
        {:error, %{reason: :error, error_message: "boom", message: msg, usage: Usage.empty()}}
      ]

      assert {:error, ^msg} = Turn.consume_llm_stream(events, "job-1", emit)
    end

    test ":start에서 :message_start emit", %{emit: emit} do
      first = %Assistant{}

      events = [
        {:start, %{message: first}},
        {:done, %{stop_reason: :stop, usage: Usage.empty(), message: %Assistant{}}}
      ]

      Turn.consume_llm_stream(events, "job-1", emit)

      assert_received {:emitted, {:message_start, %{job_id: "job-1", message: ^first}}}
    end

    test "모든 LLMRouter 이벤트가 :message_update로 중계된다", %{emit: emit} do
      events = [
        {:start, %{message: %Assistant{}}},
        {:text_delta, %{index: 0, delta: "hi"}},
        {:text_delta, %{index: 0, delta: " there"}},
        {:done, %{stop_reason: :stop, usage: Usage.empty(), message: %Assistant{}}}
      ]

      Turn.consume_llm_stream(events, "job-1", emit)

      for ev <- events do
        assert_received {:emitted, {:message_update, %{job_id: "job-1", llm_event: ^ev}}}
      end
    end

    test ":done에서 :message_end emit", %{emit: emit} do
      final = %Assistant{content: [{:text, "done"}]}

      events = [
        {:start, %{message: %Assistant{}}},
        {:done, %{stop_reason: :stop, usage: Usage.empty(), message: final}}
      ]

      Turn.consume_llm_stream(events, "job-1", emit)

      assert_received {:emitted, {:message_end, %{job_id: "job-1", message: ^final}}}
    end

    test ":error에서도 :message_end emit", %{emit: emit} do
      final = %Assistant{content: [], stop_reason: :error, error_message: "x"}

      events = [
        {:start, %{message: %Assistant{}}},
        {:error, %{reason: :error, error_message: "x", message: final, usage: Usage.empty()}}
      ]

      Turn.consume_llm_stream(events, "job-1", emit)

      assert_received {:emitted, {:message_end, %{job_id: "job-1", message: ^final}}}
    end

    test "스트림이 :done/:error 없이 끝나면 {:error, _} 반환", %{emit: emit} do
      events = [
        {:start, %{message: %Assistant{}}},
        {:text_delta, %{index: 0, delta: "incomplete"}}
      ]

      assert {:error, %Assistant{stop_reason: :error}} =
               Turn.consume_llm_stream(events, "job-1", emit)
    end
  end

  describe "take/3" do
    setup do
      test_pid = self()
      emit = fn ev -> send(test_pid, {:emitted, ev}) end
      creds = Credentials.build(:openai_codex, "access", "refresh", 3600)
      {:ok, emit: emit, creds: creds}
    end

    test "users는 빈 리스트로 시작한다 (1차엔 steering/follow_up이 없으므로)", %{emit: emit, creds: creds} do
      Process.put(:fake_router_response, ok_stream(%Assistant{}))

      job = build_job(creds)

      assert {:ok, %Turn{index: 1, users: [], tool_results: []}} =
               Turn.take(job, [], emit)
    end

    test "prev_turns 길이 + 1 이 index가 된다", %{emit: emit, creds: creds} do
      Process.put(:fake_router_response, ok_stream(%Assistant{}))

      prev = [
        %Turn{index: 1, assistant: %Assistant{}},
        %Turn{index: 2, assistant: %Assistant{}}
      ]

      job = build_job(creds)
      assert {:ok, %Turn{index: 3}} = Turn.take(job, prev, emit)
    end

    test "assistant.usage가 turn.usage에 들어간다", %{emit: emit, creds: creds} do
      usage = %Usage{input: 100, output: 50, cache_read: 0, cache_write: 0, total_tokens: 150}
      final = %Assistant{usage: usage}
      Process.put(:fake_router_response, ok_stream(final))

      job = build_job(creds)
      assert {:ok, %Turn{usage: ^usage}} = Turn.take(job, [], emit)
    end

    test "router.stream에 base context messages가 그대로 전달된다", %{
      emit: emit,
      creds: creds
    } do
      Process.put(:fake_router_response, ok_stream(%Assistant{}))

      base_msgs = [User.new("first")]
      job = build_job(creds, context: Context.new(messages: base_msgs))
      Turn.take(job, [], emit)

      assert_received {:fake_router_called, %{ctx: %Context{messages: ^base_msgs}}}
    end

    test "prev_turns가 있으면 base 뒤에 as_llm_messages가 이어진다", %{
      emit: emit,
      creds: creds
    } do
      Process.put(:fake_router_response, ok_stream(%Assistant{}))

      base_msgs = [User.new("first")]

      prev_turn = %Turn{
        index: 1,
        users: [],
        assistant: %Assistant{content: [{:text, "answer1"}]},
        tool_results: []
      }

      job = build_job(creds, context: Context.new(messages: base_msgs))
      Turn.take(job, [prev_turn], emit)

      expected = base_msgs ++ Turn.as_llm_messages(prev_turn)
      assert_received {:fake_router_called, %{ctx: %Context{messages: ^expected}}}
    end

    test "router.stream에 model, creds, session_id, llm_opts가 전달된다", %{
      emit: emit,
      creds: creds
    } do
      Process.put(:fake_router_response, ok_stream(%Assistant{}))

      job = %{build_job(creds) | llm_opts: [reasoning_effort: :low]}
      Turn.take(job, [], emit)

      assert_received {:fake_router_called,
                       %{
                         model: %Model{id: "test"},
                         creds: ^creds,
                         session_id: "s1",
                         opts: [reasoning_effort: :low]
                       }}
    end

    test "credential_fun 실패면 {:error, reason}", %{emit: emit} do
      job = build_job(nil, credential_fun: fn -> {:error, :token_expired} end)
      assert {:error, :token_expired} = Turn.take(job, [], emit)
    end

    test "router.stream이 {:error, _} 반환하면 {:error, reason}", %{emit: emit, creds: creds} do
      Process.put(:fake_router_response, {:error, :network})
      job = build_job(creds)
      assert {:error, :network} = Turn.take(job, [], emit)
    end

    test "LLM 응답이 :error로 끝나면 {:error, %Turn{}}을 반환", %{emit: emit, creds: creds} do
      error_msg = %Assistant{stop_reason: :error, error_message: "boom"}

      Process.put(
        :fake_router_response,
        {:ok,
         [
           {:start, %{message: %Assistant{}}},
           {:error,
            %{reason: :error, error_message: "boom", message: error_msg, usage: Usage.empty()}}
         ]}
      )

      job = build_job(creds)
      assert {:error, %Turn{index: 1, assistant: ^error_msg}} = Turn.take(job, [], emit)
    end
  end

  defp build_job(creds, opts \\ []) do
    %Job{
      model: %Model{id: "test", provider: :test},
      credential_fun: Keyword.get(opts, :credential_fun, fn -> {:ok, creds} end),
      session_id: "s1",
      context: Keyword.get(opts, :context, Context.new(messages: [User.new("hi")])),
      job_id: "j1"
    }
  end

  defp ok_stream(final_assistant) do
    {:ok,
     [
       {:start, %{message: %Assistant{}}},
       {:done, %{stop_reason: :stop, usage: Usage.empty(), message: final_assistant}}
     ]}
  end
end
