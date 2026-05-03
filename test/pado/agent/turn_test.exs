defmodule Pado.Agent.TurnTest do
  use ExUnit.Case, async: true

  alias Pado.Agent.{Job, Tool, Turn}
  alias Pado.LLM.{Context, Model, Usage}
  alias Pado.LLM.Message.{Assistant, ToolResult, User}
  alias Pado.LLM.Credential.OAuth.Credentials
  alias Pado.LLM.Tool, as: LLMTool

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

    test "모든 LLM 이벤트가 :message_update로 중계된다", %{emit: emit} do
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

  describe "take/2" do
    setup do
      test_pid = self()
      emit = fn ev -> send(test_pid, {:emitted, ev}) end
      creds = Credentials.build(:openai_codex, "access", "refresh", 3600)
      {:ok, emit: emit, creds: creds}
    end

    test "새 turn이 job.turns 끝에 추가된 갱신된 Job을 반환한다", %{emit: emit, creds: creds} do
      Process.put(:fake_router_response, ok_stream(%Assistant{}))
      job = build_job(creds)

      assert {:ok, %Job{turns: turns}} = Turn.take(job, emit)
      assert [%Turn{index: 1, users: [], tool_results: []}] = turns
    end

    test "job.turns 길이 + 1 이 새 turn의 index가 된다", %{emit: emit, creds: creds} do
      Process.put(:fake_router_response, ok_stream(%Assistant{}))

      prev = [
        %Turn{index: 1, assistant: %Assistant{}},
        %Turn{index: 2, assistant: %Assistant{}}
      ]

      job = %{build_job(creds) | turns: prev}
      assert {:ok, %Job{turns: turns}} = Turn.take(job, emit)
      assert [_, _, %Turn{index: 3}] = turns
    end

    test "assistant.usage가 새 turn.usage에 들어간다", %{emit: emit, creds: creds} do
      usage = %Usage{input: 100, output: 50, cache_read: 0, cache_write: 0, total_tokens: 150}
      final = %Assistant{usage: usage}
      Process.put(:fake_router_response, ok_stream(final))

      job = build_job(creds)
      assert {:ok, %Job{turns: [%Turn{usage: ^usage}]}} = Turn.take(job, emit)
    end

    test "router.stream에 job.tools의 definition 목록이 ctx.tools로 전달된다", %{
      emit: emit,
      creds: creds
    } do
      Process.put(:fake_router_response, ok_stream(%Assistant{}))

      tool_a = make_tool("search", fn _, _ -> "a" end)
      tool_b = make_tool("fetch", fn _, _ -> "b" end)
      job = build_job(creds, tools: [tool_a, tool_b])
      Turn.take(job, emit)

      expected = [tool_a.definition, tool_b.definition]
      assert_received {:fake_router_called, %{ctx: %Context{tools: ^expected}}}
    end

    test "첫 Turn에 router.stream에 base context messages가 그대로 전달된다", %{
      emit: emit,
      creds: creds
    } do
      Process.put(:fake_router_response, ok_stream(%Assistant{}))

      base_msgs = [User.new("first")]
      job = build_job(creds, context: Context.new(messages: base_msgs))
      Turn.take(job, emit)

      assert_received {:fake_router_called, %{ctx: %Context{messages: ^base_msgs}}}
    end

    test "job.turns가 있으면 base 뒤에 as_llm_messages가 이어진다", %{
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

      job = %{
        build_job(creds, context: Context.new(messages: base_msgs))
        | turns: [prev_turn]
      }

      Turn.take(job, emit)

      expected = base_msgs ++ Turn.as_llm_messages(prev_turn)
      assert_received {:fake_router_called, %{ctx: %Context{messages: ^expected}}}
    end

    test "router.stream에 model, creds, session_id, llm_opts가 전달된다", %{
      emit: emit,
      creds: creds
    } do
      Process.put(:fake_router_response, ok_stream(%Assistant{}))

      job = %{build_job(creds) | llm_opts: [reasoning_effort: :low]}
      Turn.take(job, emit)

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
      assert {:error, :token_expired} = Turn.take(job, emit)
    end

    test "router.stream이 {:error, _} 반환하면 {:error, reason}", %{emit: emit, creds: creds} do
      Process.put(:fake_router_response, {:error, :network})
      job = build_job(creds)
      assert {:error, :network} = Turn.take(job, emit)
    end

    test "assistant가 tool_call을 요청하면 새 turn.tool_results에 순서대로 들어간다",
         %{emit: emit, creds: creds} do
      tool = make_tool("echo", fn args, _ -> args["text"] end)

      asst = %Assistant{
        content: [
          {:text, "echo 호출"},
          {:tool_call, %{id: "c1", name: "echo", args: %{"text" => "hi"}}},
          {:tool_call, %{id: "c2", name: "echo", args: %{"text" => "bye"}}}
        ]
      }

      Process.put(:fake_router_response, ok_stream(asst))
      job = build_job(creds, tools: [tool])

      assert {:ok, %Job{turns: [%Turn{tool_results: [tr1, tr2]}]}} = Turn.take(job, emit)
      assert tr1.tool_call_id == "c1"
      assert tr1.content == [{:text, "hi"}]
      assert tr2.tool_call_id == "c2"
      assert tr2.content == [{:text, "bye"}]
    end

    test "unknown tool은 ToolResult.error로 turn에 들어간다", %{emit: emit, creds: creds} do
      asst = %Assistant{
        content: [{:tool_call, %{id: "c1", name: "missing", args: %{}}}]
      }

      Process.put(:fake_router_response, ok_stream(asst))
      job = build_job(creds, tools: [])

      assert {:ok, %Job{turns: [%Turn{tool_results: [tr]}]}} = Turn.take(job, emit)
      assert tr.is_error == true
    end

    test "tool_call마다 :tool_execution_start / :tool_execution_end를 emit한다", %{
      emit: emit,
      creds: creds
    } do
      tool = make_tool("echo", fn _, _ -> "ok" end)

      asst = %Assistant{
        content: [{:tool_call, %{id: "c1", name: "echo", args: %{"k" => "v"}}}]
      }

      Process.put(:fake_router_response, ok_stream(asst))
      job = build_job(creds, tools: [tool])
      Turn.take(job, emit)

      assert_received {:emitted,
                       {:tool_execution_start,
                        %{
                          job_id: "j1",
                          turn_index: 1,
                          tool_call_id: "c1",
                          tool_name: "echo",
                          args: %{"k" => "v"}
                        }}}

      assert_received {:emitted,
                       {:tool_execution_end,
                        %{
                          job_id: "j1",
                          turn_index: 1,
                          tool_call_id: "c1",
                          tool_name: "echo",
                          is_error: false
                        }}}
    end

    test "assistant에 tool_call이 없으면 tool_results는 빈 리스트", %{
      emit: emit,
      creds: creds
    } do
      Process.put(:fake_router_response, ok_stream(%Assistant{content: [{:text, "끝"}]}))
      job = build_job(creds, tools: [make_tool("echo", fn _, _ -> "x" end)])

      assert {:ok, %Job{turns: [%Turn{tool_results: []}]}} = Turn.take(job, emit)
    end

    test "LLM 응답이 :error로 끝나면 {:error, %Job{...}}을 반환 (마지막 turn은 error turn)",
         %{emit: emit, creds: creds} do
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

      assert {:error, %Job{turns: [%Turn{index: 1, assistant: ^error_msg}]}} =
               Turn.take(job, emit)
    end
  end

  defp build_job(creds, opts \\ []) do
    %Job{
      model: %Model{id: "test", provider: :test},
      credential_fun: Keyword.get(opts, :credential_fun, fn -> {:ok, creds} end),
      session_id: "s1",
      context: Keyword.get(opts, :context, Context.new(messages: [User.new("hi")])),
      tools: Keyword.get(opts, :tools, []),
      job_id: "j1"
    }
  end

  describe "tool_calls/1" do
    test "content에서 tool_call 블록만 순서대로 추출" do
      tc1 = %{id: "c1", name: "search", args: %{q: "x"}}
      tc2 = %{id: "c2", name: "fetch", args: %{u: "y"}}

      assistant = %Assistant{
        content: [
          {:text, "자, 다음 작업 할게"},
          {:tool_call, tc1},
          {:thinking, "..."},
          {:tool_call, tc2}
        ]
      }

      assert Turn.tool_calls(assistant) == [tc1, tc2]
    end

    test "tool_call이 없으면 빈 리스트" do
      assistant = %Assistant{content: [{:text, "그냥 응답"}]}
      assert Turn.tool_calls(assistant) == []
    end

    test "빈 content면 빈 리스트" do
      assert Turn.tool_calls(%Assistant{content: []}) == []
    end
  end

  describe "find_tool/2" do
    test "name이 일치하는 tool을 반환" do
      a = make_tool("search", fn _, _ -> "a" end)
      b = make_tool("fetch", fn _, _ -> "b" end)

      assert Turn.find_tool([a, b], "fetch") == b
    end

    test "일치 없으면 nil" do
      a = make_tool("search", fn _, _ -> "a" end)
      assert Turn.find_tool([a], "unknown") == nil
    end

    test "tools가 비어있으면 nil" do
      assert Turn.find_tool([], "any") == nil
    end
  end

  describe "dispatch_tool/2" do
    test "unknown tool은 ToolResult.error" do
      call = %{id: "c1", name: "missing", args: %{}}
      result = Turn.dispatch_tool(call, [])

      assert %ToolResult{tool_call_id: "c1", tool_name: "missing", is_error: true} = result
    end

    test "정상 실행 + string 반환은 ToolResult.text" do
      tools = [make_tool("echo", fn args, _ -> args["text"] end)]
      call = %{id: "c1", name: "echo", args: %{"text" => "hello"}}

      result = Turn.dispatch_tool(call, tools)
      assert %ToolResult{is_error: false, content: [{:text, "hello"}]} = result
    end

    test "non-string 반환은 inspect로 문자열화" do
      tools = [make_tool("sum", fn args, _ -> args["a"] + args["b"] end)]
      call = %{id: "c1", name: "sum", args: %{"a" => 1, "b" => 2}}

      result = Turn.dispatch_tool(call, tools)
      assert %ToolResult{is_error: false, content: [{:text, "3"}]} = result
    end

    test "실행 중 raise는 ToolResult.error" do
      tools = [make_tool("boom", fn _, _ -> raise "폭발" end)]
      call = %{id: "c1", name: "boom", args: %{}}

      result = Turn.dispatch_tool(call, tools)
      assert %ToolResult{is_error: true} = result
      assert [{:text, msg}] = result.content
      assert msg =~ "폭발"
    end
  end

  defp make_tool(name, execute) do
    %Tool{
      definition: LLMTool.new(name, "테스트 도구", %{}),
      execute: execute
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
